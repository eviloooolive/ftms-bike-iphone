import Foundation
import CoreBluetooth
import Combine

/// 蓝牙管理器：扫描 / 连接 / 订阅 / 控制 FTMS 单车。
/// 单例，供 SwiftUI 各视图通过 @EnvironmentObject 共享。
final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    // MARK: - 对外状态（@Published）
    @Published var managerState: ManagerState = .unknown
    @Published var discovered: [DiscoveredDevice] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedName: String = ""
    @Published var logLines: [String] = []

    @Published var latest = IndoorBikeSample()
    @Published var lastUpdate = Date()

    // 各指标的滚动缓冲（用于趋势图，最多保留 maxPoints 点）
    @Published var speedSeries: [Double] = []
    @Published var cadenceSeries: [Double] = []
    @Published var powerSeries: [Double] = []
    @Published var heartRateSeries: [Double] = []
    @Published var distanceSeries: [Double] = []
    @Published var energySeries: [Double] = []
    @Published var statusEvents: [StatusEvent] = []
    @Published var controlResponses: [ControlResponseEvent] = []
    /// 当前阻力档位（程序本地记录，因为 MRK 不回传阻力值）。
    @Published var resistanceLevel: Int = 0

    // 调试用：暴露原始累计值与每秒增量，便于确认字段单位（转数/米）。
    @Published var lastCumRevsValue: UInt16 = 0
    @Published var lastCadenceRate: Double = 0
    @Published var lastDistanceRaw: UInt32 = 0    // 设备距离位原始 uint24 值（调试用）

    // MARK: - 私有
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var indoorBikeChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var devices: [UUID: CBPeripheral] = [:]
    private let maxPoints = 120

    // 踏频/距离换算状态：MRK 的“踏频”位发的是累计计数值，需做差分得到瞬时踏频。
    private var lastCumRevs: UInt16?
    private var lastCumTime: Date?
    private var smoothedCadence: Double = 0
    private let metersPerRev: Double = 2.0   // 每转等效里程（米），用于把累计转数换算成距离
    private var syncTimer: Timer?

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    // MARK: - 扫描 / 连接
    func startScan() {
        discovered.removeAll()
        devices.removeAll()
        guard managerState == .poweredOn else {
            appendLog("蓝牙未开启，请在系统设置中打开蓝牙")
            return
        }
        // 不过滤服务 UUID 全扫：部分单车（如 MRK）广播里不带 0x1826，
        // 但连接后仍能发现 FTMS 服务。连接时再校验是否真为 FTMS 设备。
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        connectionState = .scanning
        appendLog("开始扫描周围蓝牙设备…（连接后会校验是否为 FTMS 单车）")
    }

    func stopScan() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .disconnected }
        appendLog("停止扫描")
    }

    func connect(_ device: DiscoveredDevice) {
        guard let p = devices[device.id] else { return }
        p.delegate = self
        peripheral = p
        connectionState = .connecting
        central.stopScan()
        central.connect(p, options: nil)
        appendLog("正在连接 \(device.name) …")
    }

    func disconnect() {
        stopResistanceSync()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        appendLog("主动断开")
    }

    // MARK: - 控制指令
    func requestControl() { sendControl(.requestControl) }
    func start() { sendControl(.startResume) }
    func stop() { sendControl(.stopPause, params: Data([0x01])) }
    /// 重置：下发设备 reset 指令，并清空 App 本地骑行数据（device 不支持时本地也能归零）。
    func reset() {
        sendControl(.reset)
        resetLocalState()
        appendLog("已重置本地骑行数据（设备重置指令已下发）")
    }

    func setResistance(_ level: Int) {
        let clamped = min(max(level, 0), 100)
        resistanceLevel = clamped
        var v = Int16(clamped * 10).littleEndian
        let params = Data(bytes: &v, count: 2)
        sendControl(.setResistance, params: params)
        appendLog("下发阻力 -> \(clamped) 档 (值 \(clamped * 10))")
    }

    private func sendControl(_ op: ControlOp, params: Data? = nil) {
        guard let char = controlChar, let p = peripheral else {
            appendLog("控制点未就绪，请先连接设备")
            return
        }
        var payload = Data([op.rawValue])
        if let params = params { payload.append(params) }
        p.writeValue(payload, for: char, type: .withResponse)
    }

    // MARK: - 阻力实时同步
    /// 启动定时器：每 2.5s 把 App 当前的阻力档位重新写回单车，
    /// 保证车与 App 阻力始终一致（MRK 不回传阻力，因此 App 作为唯一控制源强制同步）。
    private func startResistanceSync() {
        stopResistanceSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.reassertResistance()
        }
    }

    private func stopResistanceSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func reassertResistance() {
        guard let char = controlChar, let p = peripheral, connectionState == .connected else { return }
        var v = Int16(resistanceLevel * 10).littleEndian
        let params = Data(bytes: &v, count: 2)
        var payload = Data([ControlOp.setResistance.rawValue])
        payload.append(params)
        p.writeValue(payload, for: char, type: .withResponse)
    }

    // MARK: - 本地状态清空（断线 / 重置时调用）
    private func resetLocalState() {
        latest = IndoorBikeSample()
        speedSeries.removeAll(); cadenceSeries.removeAll(); powerSeries.removeAll()
        heartRateSeries.removeAll(); distanceSeries.removeAll(); energySeries.removeAll()
        lastCumRevs = nil; lastCumTime = nil; smoothedCadence = 0
        lastCumRevsValue = 0; lastCadenceRate = 0
    }

    // MARK: - 日志 / 工具
    private func appendLog(_ s: String) {
        let line = "\(timeFmt.string(from: Date()))  \(s)"
        DispatchQueue.main.async {
            self.logLines.insert(line, at: 0)
            if self.logLines.count > 200 { self.logLines.removeLast() }
        }
    }

    /// 追加一个点到滚动缓冲，超过上限则丢弃最旧的点。
    private func append(_ arr: [Double], _ v: Double?) -> [Double] {
        guard let v = v else { return arr }
        var a = arr
        a.append(v)
        if a.count > maxPoints { a.removeFirst() }
        return a
    }

    // MARK: - 解析：Indoor Bike Data (2AD2)
    /// 兼容 MRK-S10M-96ED 的非标准帧：
    /// - 0x0075 帧把 bit5(阻力) 错误置位，但距离后只剩 1 字节是 uint8 功率；
    /// - 0x0B00 帧不含速度(bit0)，避免把能量误读成速度；
    /// - “踏频”位(bit2)上发的是**累计计数值**（非瞬时踏频），单独存到 cumRevsRaw 供后续差分。
    static func parseIndoorBikeData(_ data: Data) -> IndoorBikeSample {
        var s = IndoorBikeSample()
        guard data.count >= 4 else { return s }
        let flags = u16(data, 0)
        var off = 2
        let count = data.count

        // 每个字段读取前都做边界检查，避免真机收到截断帧时越界崩溃。
        if flags & 0x0001 != 0, off + 2 <= count { s.speedKmph = Double(u16(data, off)) / 100.0; off += 2 }
        if flags & 0x0002 != 0, off + 2 <= count { off += 2 }                              // 平均速度
        if flags & 0x0004 != 0, off + 2 <= count { s.cumRevsRaw = u16(data, off); off += 2 } // 累计计数（非瞬时踏频）
        if flags & 0x0008 != 0, off + 2 <= count { off += 2 }                              // 平均踏频
        if flags & 0x0010 != 0, off + 3 <= count { let d = u24(data, off); s.distanceRaw = d; s.distanceM = Double(d); off += 3 } // 设备标准距离位(uint24 绝对米数)，优先使用

        let hasRes = (flags & 0x0020) != 0
        let hasPow = (flags & 0x0040) != 0
        let remaining = count - off
        if hasRes && hasPow && remaining >= 4 {
            s.resistance = Int(Int16(bitPattern: u16(data, off))); off += 2
            s.powerW = Int(Int16(bitPattern: u16(data, off))); off += 2
        } else if hasPow && remaining >= 2 {
            s.powerW = Int(Int16(bitPattern: u16(data, off))); off += 2
            if hasRes && (count - off) >= 2 {
                s.resistance = Int(Int16(bitPattern: u16(data, off))); off += 2
            }
        } else if hasRes && remaining >= 2 {
            s.resistance = Int(Int16(bitPattern: u16(data, off))); off += 2
        } else if hasPow && remaining == 1 {
            s.powerW = Int(data[off]); off += 1   // MRK 非标准 uint8 功率
        }

        if flags & 0x0080 != 0, off + 2 <= count { off += 2 }                              // 平均功率
        if flags & 0x0100 != 0 {                                                          // 消耗能量(5 字节)
            if off + 5 <= count { s.energyKcal = Double(u16(data, off)) / 10.0 }
            off += 5
        }
        if flags & 0x0200 != 0, off + 1 <= count { s.heartRate = Int(data[off]); off += 1 }
        if flags & 0x0400 != 0, off + 1 <= count { off += 1 }                              // 代谢当量
        if flags & 0x0800 != 0, off + 2 <= count { off += 2 }                              // 经过时间
        if flags & 0x1000 != 0, off + 2 <= count { off += 2 }                              // 剩余时间
        if flags & 0x2000 != 0, off + 1 <= count { off += 1 }                              // 运动方向
        return s
    }

    private static func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }
    private static func u24(_ d: Data, _ i: Int) -> UInt32 {
        UInt32(d[i]) | (UInt32(d[i + 1]) << 8) | (UInt32(d[i + 2]) << 16)
    }

    // MARK: - 解析：状态包 / 控制响应
    private func parseStatus(_ data: Data) {
        guard data.count >= 1 else { return }
        let op = data[0]
        var name = "状态"
        var detail = ""
        switch op {
        case 0x01: name = "重置"
        case 0x02: name = "停止/暂停"; if data.count > 1 { detail = data[1] == 0x01 ? "(已停止)" : "(已暂停)" }
        case 0x03: name = "开始/恢复"
        case 0x04: name = "速度范围上报"
        case 0x05: name = "倾斜范围上报"
        case 0x06: name = "阻力范围上报"
        case 0x07: name = "功率范围上报"
        case 0x08: name = "阻力已变更"; if data.count >= 3 { let lvl = Double(Int16(bitPattern: Self.u16(data, 1))) / 10.0; detail = String(format: "(%.0f 档)", lvl) }
        case 0x09: name = "功率已变更"
        case 0x0A: name = "心率已变更"
        default: name = String(format: "状态 0x%02X", op)
        }
        let ev = StatusEvent(name: name, detail: detail, timestamp: Date())
        DispatchQueue.main.async {
            self.statusEvents.insert(ev, at: 0)
            if self.statusEvents.count > 60 { self.statusEvents.removeLast() }
        }
    }

    private func parseControlResponse(_ data: Data) {
        guard data.count >= 3, data[0] == 0x80 else { return }
        let op = data[1]; let result = data[2]
        let opName = ControlOp(rawValue: op)?.label ?? String(format: "指令 0x%02X", op)
        let resultName = ControlResult(rawValue: result)?.label ?? String(format: "未知 0x%02X", result)
        let ev = ControlResponseEvent(opName: opName, resultName: resultName, timestamp: Date())
        appendLog("[控制响应] \(opName) -> \(resultName)")
        DispatchQueue.main.async {
            self.controlResponses.insert(ev, at: 0)
            if self.controlResponses.count > 60 { self.controlResponses.removeLast() }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:    managerState = .poweredOn
        case .poweredOff:   managerState = .poweredOff
        case .resetting:    managerState = .resetting
        case .unauthorized: managerState = .unauthorized
        case .unsupported:  managerState = .unsupported
        case .unknown:      managerState = .unknown
        @unknown default:   managerState = .unknown
        }
        if managerState == .poweredOn { appendLog("蓝牙已就绪") }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                  ?? peripheral.name
                  ?? "未知设备"
        devices[peripheral.identifier] = peripheral
        let dev = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let idx = discovered.firstIndex(where: { $0.id == dev.id }) {
            discovered[idx] = dev
        } else {
            discovered.append(dev)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .discovering
        connectedName = peripheral.name ?? "动感单车"
        appendLog("已连接：\(connectedName)")
        peripheral.discoverServices([FTMS.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        appendLog("连接失败：\(error?.localizedDescription ?? "未知")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        indoorBikeChar = nil; statusChar = nil; controlChar = nil
        stopResistanceSync()
        resetLocalState()
        appendLog("已断开：\(error?.localizedDescription ?? "正常")")
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        guard services.contains(where: { $0.uuid == FTMS.service }) else {
            connectionState = .disconnected
            appendLog("该设备不包含 FTMS 服务，可能不是动感单车，已断开")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        for s in services where s.uuid == FTMS.service {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            switch c.uuid {
            case FTMS.indoorBikeData:
                indoorBikeChar = c
                peripheral.setNotifyValue(true, for: c)
            case FTMS.fitnessStatus:
                statusChar = c
                peripheral.setNotifyValue(true, for: c)
            case FTMS.controlPoint:
                controlChar = c
                peripheral.setNotifyValue(true, for: c)   // 接收控制响应(Indication)
            default: break
            }
        }
        connectionState = .connected
        appendLog("特征订阅完成，开始接收数据")
        requestControl()
        reassertResistance()      // 连上即把 App 阻力档位同步到车
        startResistanceSync()     // 之后每 2.5s 保持同步
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let value = characteristic.value else { return }
        if characteristic.uuid == FTMS.indoorBikeData {
            let s = BluetoothManager.parseIndoorBikeData(value)
            DispatchQueue.main.async {
                // 从上一帧继承踏频/距离，避免 0x0B00 能量帧到来时把它们清零。
                var updated = self.latest
                updated.speedKmph = s.speedKmph
                updated.powerW = s.powerW
                updated.energyKcal = s.energyKcal
                if let d = s.distanceM { updated.distanceM = d }   // 优先用设备标准距离位（uint24 绝对米数）
                if let raw = s.cumRevsRaw {
                    let now = Date()
                    if let last = self.lastCumRevs, let lastT = self.lastCumTime {
                        let dt = now.timeIntervalSince(lastT)
                        if dt > 0 {
                            var delta = Int(raw) - Int(last)
                            if delta < -32768 { delta += 65536 }      // 16 位回绕
                            else if delta > 32768 { delta -= 65536 }
                            let rate = Double(delta) / dt             // 每秒增量（转/秒）
                            self.lastCadenceRate = rate
                            let instCad = rate * 60.0                 // 瞬时踏频 RPM
                            self.smoothedCadence = self.smoothedCadence * 0.6 + max(0, instCad) * 0.4
                        }
                    }
                    self.lastCumRevs = raw
                    self.lastCumTime = now
                    self.lastCumRevsValue = raw
                    updated.cadenceRpm = max(0, self.smoothedCadence)
                    if s.distanceM == nil { updated.distanceM = Double(raw) * self.metersPerRev }  // 无距离位时回退估算
                }
                if let dRaw = s.distanceRaw { self.lastDistanceRaw = dRaw }
                self.latest = updated
                self.speedSeries     = self.append(self.speedSeries, updated.speedKmph)
                self.cadenceSeries   = self.append(self.cadenceSeries, updated.cadenceRpm)
                self.powerSeries     = self.append(self.powerSeries, updated.powerW.map(Double.init))
                self.heartRateSeries = self.append(self.heartRateSeries, updated.heartRate.map(Double.init))
                self.distanceSeries  = self.append(self.distanceSeries, updated.distanceM)
                self.energySeries    = self.append(self.energySeries, updated.energyKcal)
                self.lastUpdate = Date()
            }
        } else if characteristic.uuid == FTMS.fitnessStatus {
            parseStatus(value)
        } else if characteristic.uuid == FTMS.controlPoint {
            parseControlResponse(value)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error { appendLog("写指令失败：\(e.localizedDescription)") }
    }
}

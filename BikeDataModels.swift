import Foundation

/// 一包 Indoor Bike Data 解析结果（可选字段表示该帧是否携带）。
struct IndoorBikeSample {
    var speedKmph: Double?
    var cadenceRpm: Double?
    var distanceM: Double?
    var resistance: Int?
    var powerW: Int?
    var energyKcal: Double?
    var heartRate: Int?
    /// MRK 在“踏频”位(bit2)上发的是累计计数值（转数），并非瞬时踏频；
    /// 由 BluetoothManager 差分得到稳定踏频，原始值留此用于调试。
    var cumRevsRaw: UInt16?
    /// 设备标准距离位(bit4, uint24 绝对米数) 的原始值，用于确认距离是否随骑行增长。
    var distanceRaw: UInt32?
}

/// 扫描发现的设备（UI 用，可识别）。
struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// 设备状态变化事件（来自 2ADA）。
struct StatusEvent: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let timestamp: Date
}

/// 控制响应事件（来自 2AD9 的 Indication）。
struct ControlResponseEvent: Identifiable {
    let id = UUID()
    let opName: String
    let resultName: String
    let timestamp: Date
}

/// 蓝牙中心设备状态（对应 CBCentralManager.state）。
enum ManagerState: String { case poweredOff, poweredOn, unknown, resetting, unsupported, unauthorized }

/// 与单车的连接状态机。
enum ConnectionState: String { case disconnected, scanning, connecting, discovering, connected }

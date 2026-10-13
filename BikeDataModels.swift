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

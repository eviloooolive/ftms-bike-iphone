import Foundation
import CoreBluetooth

/// 蓝牙 SIG 标准 Fitness Machine Service (FTMS) 相关定义。
enum FTMS {
    /// 主服务 UUID（16-bit: 0x1826）
    static let service        = CBUUID(string: "1826")
    /// Indoor Bike Data：实时骑行数据（Notify）
    static let indoorBikeData = CBUUID(string: "2AD2")
    /// Fitness Machine Status：设备状态变化（Notify）
    static let fitnessStatus  = CBUUID(string: "2ADA")
    /// Fitness Machine Control Point：控制入口（Write + Indicate）
    static let controlPoint   = CBUUID(string: "2AD9")
    /// Fitness Machine Feature：能力清单（Read）
    static let fitnessFeature = CBUUID(string: "2ACC")
    /// Supported Resistance Level Range：阻力范围（Read）
    static let supResistance  = CBUUID(string: "2AD6")
}

/// 控制点 Opcode（发往 CONTROL_POINT）。
enum ControlOp: UInt8 {
    case requestControl = 0x00
    case reset          = 0x01
    case setResistance  = 0x04   // 参数：sint16，0.1 分辨率（即 档位×10）
    case startResume    = 0x07
    case stopPause      = 0x08   // 参数：0x01=停止

    var label: String {
        switch self {
        case .requestControl: return "请求控制权"
        case .reset:          return "重置"
        case .setResistance:  return "设置阻力"
        case .startResume:    return "开始/恢复"
        case .stopPause:      return "停止/暂停"
        }
    }
}

/// 控制响应结果码（响应首字节为 0x80，次字节为原 Opcode，第三字节为结果）。
enum ControlResult: UInt8 {
    case success          = 0x01
    case notSupported     = 0x02
    case invalidParameter = 0x03
    case failed           = 0x04
    case notPermitted     = 0x05

    var label: String {
        switch self {
        case .success:          return "成功"
        case .notSupported:     return "不支持"
        case .invalidParameter: return "参数错误"
        case .failed:           return "执行失败"
        case .notPermitted:     return "控制未授权（需先请求控制权）"
        }
    }
}

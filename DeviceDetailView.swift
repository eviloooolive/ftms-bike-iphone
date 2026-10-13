import SwiftUI

/// 连接后的详情页：连接状态 + 实时数值 + 趋势图 + 控制 + 日志。
struct DeviceDetailView: View {
    @EnvironmentObject var manager: BluetoothManager
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 连接状态
                HStack {
                    Circle()
                        .fill(manager.connectionState == .connected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(statusText).font(.subheadline)
                    Spacer()
                    Button("断开") { manager.disconnect() }
                        .foregroundColor(.red)
                }
                Text(manager.connectedName).font(.title2.bold())

                // 当前数值卡片
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(title: "速度", value: fmt(manager.latest.speedKmph, "km/h"))
                    MetricCard(title: "踏频", value: fmt(manager.latest.cadenceRpm, "RPM"))
                    MetricCard(title: "功率", value: fmtD(manager.latest.powerW, "W"))
                    MetricCard(title: "阻力(本地)", value: "\(manager.resistanceLevel) 档")
                    MetricCard(title: "距离", value: fmt(manager.latest.distanceM, "m"))
                    MetricCard(title: "能耗", value: fmt(manager.latest.energyKcal, "kcal"))
                    MetricCard(title: "更新", value: timeAgo)
                }

                // 实时趋势图
                Text("实时趋势").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    LineChartView(title: "速度", data: manager.speedSeries, color: .blue, unit: "km/h")
                    LineChartView(title: "踏频", data: manager.cadenceSeries, color: .green, unit: "RPM")
                    LineChartView(title: "功率", data: manager.powerSeries, color: .orange, unit: "W")
                    LineChartView(title: "距离", data: manager.distanceSeries, color: .purple, unit: "m")
                    LineChartView(title: "能耗", data: manager.energySeries, color: .teal, unit: "kcal")
                }

                // 控制
                ControlPanelView()

                // 设备状态 / 控制响应
                Text("设备状态 / 控制响应").font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(manager.statusEvents) { ev in
                        Text("• \(ev.name)\(ev.detail)").font(.caption)
                    }
                    Divider()
                    ForEach(manager.controlResponses) { ev in
                        Text("• \(ev.opName) → \(ev.resultName)")
                            .font(.caption)
                            .foregroundColor(ev.resultName == "成功" ? .green : .red)
                    }
                }

                // 调试字段（确认 MRK 数据单位用，普通使用可忽略）
                DisclosureGroup("调试字段（确认数据单位）") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("踏频位累计值 cumRevsRaw：\(manager.lastCumRevsValue)").font(.system(.caption, design: .monospaced))
                        Text("踏频位每秒增量 rate：\(String(format: "%.3f", manager.lastCadenceRate)) 转/秒").font(.system(.caption, design: .monospaced))
                        Text("设备距离位 distanceRaw(原始uint24)：\(manager.lastDistanceRaw) m").font(.system(.caption, design: .monospaced))
                        Text("判读：① 稳定蹬踏时 rate 应≈2.27 转/秒（=136RPM/60）；若你看到稳态≈6~7，说明该字段是飞轮转数(约×3)，踏频需÷3，请告诉我。② distanceRaw 若随蹬踏稳定增长，则『距离』已是设备真实值（已不再用估算系数）。").font(.caption2).foregroundColor(.secondary)
                    }
                }

                // 原始日志
                DisclosureGroup("原始日志") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(manager.logLines.indices, id: \.self) { i in
                            Text(manager.logLines[i]).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("骑行数据")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        switch manager.connectionState {
        case .connecting:  return "连接中…"
        case .discovering: return "发现服务中…"
        case .connected:   return "已连接"
        default:           return "未连接"
        }
    }

    private var timeAgo: String {
        let s = Int(Date().timeIntervalSince(manager.lastUpdate))
        return "\(max(s, 0))s 前"
    }

    private func fmt(_ v: Double?, _ unit: String) -> String {
        guard let v = v else { return "-- \(unit)" }
        return String(format: "%.1f %@", v, unit)
    }
    private func fmtD(_ v: Int?, _ unit: String) -> String {
        guard let v = v else { return "-- \(unit)" }
        return "\(v) \(unit)"
    }
}

/// 单个数值卡片。
struct MetricCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
    }
}

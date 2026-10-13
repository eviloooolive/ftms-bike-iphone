import SwiftUI

/// 手动控制面板：阻力滑杆 + 开始/停止/重置。
struct ControlPanelView: View {
    @EnvironmentObject var manager: BluetoothManager
    @State private var resValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动控制").font(.headline)

            HStack {
                Text("阻力档位")
                Spacer()
                Text("\(manager.resistanceLevel) 档").bold()
            }
            Slider(value: $resValue, in: 0...32, step: 1, onEditingChanged: { editing in
                // 仅在松手时下发，避免拖动过程中刷屏式写 BLE
                if !editing { manager.setResistance(Int(resValue)) }
            }) {
                Text("阻力")
            }
            .onAppear { resValue = Double(manager.resistanceLevel) }

            HStack(spacing: 12) {
                Button("开始 / 恢复") { manager.start() }
                    .buttonStyle(.borderedProminent)
                Button("停止 / 暂停") { manager.stop() }
                    .buttonStyle(.bordered)
                Button("重置") { manager.reset() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

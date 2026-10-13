import SwiftUI

/// 扫描并选择单车。
struct DeviceScanView: View {
    @EnvironmentObject var manager: BluetoothManager

    var body: some View {
        VStack(spacing: 12) {
            if manager.managerState != .poweredOn {
                Label("请先在 iPhone 设置中打开蓝牙", systemImage: "bolt.slash.fill")
                    .foregroundColor(.red)
                    .padding()
            }

            Button(action: {
                if manager.connectionState == .scanning {
                    manager.stopScan()
                } else {
                    manager.startScan()
                }
            }) {
                Text(manager.connectionState == .scanning ? "停止扫描" : "扫描周围单车")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(manager.connectionState == .scanning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            if manager.discovered.isEmpty {
                Spacer()
                Text(manager.connectionState == .scanning
                     ? "正在搜索…请确认单车已开机并处于可发现状态"
                     : "未发现设备，点击上方按钮开始扫描")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(manager.discovered) { dev in
                    Button {
                        manager.connect(dev)
                    } label: {
                        HStack {
                            Image(systemName: "bicycle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dev.name).font(.headline)
                                Text(dev.id.uuidString).font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            Text("\(dev.rssi) dBm")
                                .foregroundColor(dev.rssi > -70 ? .green : .orange)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("选择动感单车")
    }
}

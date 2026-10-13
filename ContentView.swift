import SwiftUI

/// 顶层：底部 Tab ——「单车」(扫描/连接/详情) 与「游戏」(竞速小游戏)。
struct ContentView: View {
    @StateObject private var manager = BluetoothManager.shared

    var body: some View {
        TabView {
            ConnectionTab()
                .tabItem { Label("单车", systemImage: "bicycle") }
            BikeGameView()
                .tabItem { Label("游戏", systemImage: "flag.checkered") }
        }
        .environmentObject(manager)
    }
}

/// 「单车」Tab：根据连接状态在扫描页与详情页之间切换。
private struct ConnectionTab: View {
    @EnvironmentObject var manager: BluetoothManager

    var body: some View {
        NavigationStack {
            if manager.connectionState == .connected ||
               manager.connectionState == .connecting ||
               manager.connectionState == .discovering {
                DeviceDetailView()
                    .environmentObject(manager)
            } else {
                DeviceScanView()
                    .environmentObject(manager)
            }
        }
    }
}

import SwiftUI

/// 竞速游戏主视图：底部「游戏」Tab 入口。
struct BikeGameView: View {
    @EnvironmentObject var manager: BluetoothManager
    @StateObject private var model = GameModel()

    var body: some View {
        NavigationStack {
            TimelineView(.animation) { context in
                GameRaceView(model: model, manager: manager, date: context.date)
            }
            .navigationTitle("🚴 竞速游戏")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct GameRaceView: View {
    @ObservedObject var model: GameModel
    var manager: BluetoothManager
    var date: Date

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                hud
                ZStack {
                    Canvas { ctx, size in
                        drawRace(ctx: ctx, size: size)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if model.state == .racing {
                        VStack {
                            HStack {
                                Spacer()
                                Button("放弃") { model.reset() }
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(8)
                    }

                    if model.frozen {
                        banner("蓝牙已断开，比赛暂停中")
                    }
                    if model.state == .idle {
                        startOverlay
                    }
                    if model.state == .finished {
                        resultOverlay
                    }
                }
            }
        }
        .onChange(of: date) { newDate in
            model.tick(now: newDate,
                       cadence: manager.latest.cadenceRpm,
                       power: manager.latest.powerW,
                       connected: manager.connectionState == .connected)
        }
    }

    // MARK: - HUD
    private var hud: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("你").foregroundStyle(.blue).bold()
                    Text("\(Int(model.playerDistance)) / \(Int(model.raceDistance)) m")
                    Text("进度 \(Int(model.playerDistance / model.raceDistance * 100))%")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AI").foregroundStyle(.red).bold()
                    Text("\(Int(model.aiDistance)) / \(Int(model.raceDistance)) m")
                    Text("进度 \(Int(model.aiDistance / model.raceDistance * 100))%")
                }
            }
            .font(.caption)

            HStack(spacing: 12) {
                Label("\(Int(manager.latest.cadenceRpm ?? 0)) RPM", systemImage: "speedometer")
                Label("\(manager.latest.powerW ?? 0) W", systemImage: "bolt")
                Text(String(format: "⏱ %.1fs", model.elapsed))
                Spacer()
                boostBadge()
            }
            .font(.caption2)
            .padding(.bottom, 4)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func boostBadge() -> some View {
        if model.boostActive {
            Text("冲刺中!").foregroundStyle(.yellow).bold()
        } else if model.boostCooldownRemaining > 0 {
            Text(String(format: "冷却 %.1fs", model.boostCooldownRemaining)).foregroundStyle(.gray)
        } else {
            Text("猛蹬冲刺").foregroundStyle(.green)
        }
    }

    // MARK: - 覆盖层
    private var startOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("虚拟竞速 vs AI").font(.title2).bold()
            Text("踏频越快你跑得越快；猛蹬一下触发冲刺，瞬间超越 AI！")
                .font(.caption).multilineTextAlignment(.center).padding(.horizontal)
            if manager.connectionState == .connected {
                Button("开始竞速") { model.start() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("请先在「单车」标签连接你的动感单车")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var resultOverlay: some View {
        VStack(spacing: 14) {
            Text(model.winner == .player ? "🏆 你赢了！" : "😵 AI 赢了")
                .font(.title).bold()
                .foregroundStyle(model.winner == .player ? .green : .red)
            Text(String(format: "用时 %.1f 秒", model.elapsed))
            if model.bestWinTime > 0 {
                Text(String(format: "最佳纪录 %.1f 秒", model.bestWinTime)).font(.caption)
            }
            Button("再来一局") { model.start() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.headline).foregroundStyle(.white)
            .padding()
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
    }

    // MARK: - 赛道绘制（纯几何图形，零第三方依赖）
    private func drawRace(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(.systemGroupedBackground)))

        let laneH: CGFloat = max(40, size.height * 0.22)
        let topY = size.height * 0.26
        let botY = size.height * 0.58
        let margin: CGFloat = 24
        let trackW = size.width - margin * 2
        let finishX = margin + trackW * 0.96

        for (y, prog, tint) in [
            (topY, model.playerDistance / model.raceDistance, Color.blue),
            (botY, model.aiDistance / model.raceDistance, Color.red)
        ] {
            let rect = CGRect(x: margin, y: y, width: trackW, height: laneH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 10),
                     with: .color(Color(.secondarySystemBackground)))
            let fillW = trackW * CGFloat(min(1, max(0, prog)))
            if fillW > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: margin, y: y, width: fillW, height: laneH),
                              cornerRadius: 10),
                         with: .color(tint.opacity(0.25)))
            }
        }

        // 终点线（棋盘格简化）
        for i in 0..<Int(laneH / 8) {
            let yy = topY + CGFloat(i) * 8
            ctx.fill(Path(CGRect(x: finishX, y: yy, width: 10, height: 8)),
                     with: .color(i % 2 == 0 ? .black : .white))
        }

        let pProg = CGFloat(min(1, model.playerDistance / model.raceDistance))
        let aProg = CGFloat(min(1, model.aiDistance / model.raceDistance))
        let pX = margin + trackW * pProg
        let aX = margin + trackW * aProg
        let r: CGFloat = 16
        ctx.fill(Circle().path(in: CGRect(x: pX - r, y: topY + laneH / 2 - r, width: r * 2, height: r * 2)),
                 with: .color(.blue))
        ctx.fill(Circle().path(in: CGRect(x: aX - r, y: botY + laneH / 2 - r, width: r * 2, height: r * 2)),
                 with: .color(.red))

        if model.boostActive {
            ctx.stroke(Circle().path(in: CGRect(x: pX - r - 6, y: topY + laneH / 2 - r - 6,
                                               width: (r + 6) * 2, height: (r + 6) * 2)),
                       with: .color(.yellow), lineWidth: 3)
        }
    }
}

import Foundation
import Combine

/// 虚拟竞速游戏模型：你（真实踏频驱动）vs AI 幽灵车。
/// - 前进速度由实时踏频(cadence)映射；功率突增触发冲刺。
/// - 不使用原始 km/h（动感单车原始速度仅 0.6~1.3 km/h，不适合做游戏速度）。
final class GameModel: ObservableObject {
    enum State: String { case idle, racing, finished }
    enum Winner: String { case player, ai, none }

    // MARK: - 可调参数（手感都在这调）
    let raceDistance: Double = 1000.0      // 赛道长度（游戏米）
    let cadenceToSpeed: Double = 0.045      // 踏频(RPM) → 游戏速度(m/s)：136RPM≈6.1m/s 可甩开 AI；偷懒则 AI 反超
    let aiSpeed: Double = 4.5              // AI 匀速(m/s)，约 222s 跑完；正常蹬(~100RPM≈4.5)与之并驾
    let boostMultiplier: Double = 1.8       // 冲刺速度倍率
    let boostDuration: Double = 2.2         // 冲刺持续(s)
    let boostCooldown: Double = 4.0         // 冲刺冷却(s)
    let surgeRatio: Double = 1.5            // 功率突增判定：瞬时 > 基线*1.5
    let surgeMinPower: Double = 35.0        // 且瞬时功率 > 此值(W)
    let surgeMinBaseline: Double = 20.0     // 且基线已热身(>20W)才允许冲刺

    // MARK: - 对外状态（@Published）
    @Published var state: State = .idle
    @Published var playerDistance: Double = 0
    @Published var aiDistance: Double = 0
    @Published var elapsed: Double = 0
    @Published var boostActive: Bool = false
    @Published var boostCooldownRemaining: Double = 0
    @Published var frozen: Bool = false
    @Published var winner: Winner = .none
    @Published var bestWinTime: Double =
        UserDefaults.standard.double(forKey: "ftms_best_win_time")

    // MARK: - 内部
    private var lastDate: Date?
    private var powerBaseline: Double = 0
    private var boostTimer: Double = 0
    private var cooldownTimer: Double = 0

    // MARK: - 控制
    func start() {
        state = .racing
        playerDistance = 0; aiDistance = 0; elapsed = 0
        boostActive = false; boostCooldownRemaining = 0; frozen = false
        winner = .none; lastDate = nil; powerBaseline = 0
        boostTimer = 0; cooldownTimer = 0
    }

    func reset() {
        state = .idle
        playerDistance = 0; aiDistance = 0; elapsed = 0
        boostActive = false; boostCooldownRemaining = 0; frozen = false
        winner = .none; lastDate = nil; powerBaseline = 0
        boostTimer = 0; cooldownTimer = 0
    }

    /// 每帧调用：now 为当前时间，cadence/power 取自蓝牙实时数据。
    func tick(now: Date, cadence: Double?, power: Int?, connected: Bool) {
        guard state == .racing else { lastDate = now; return }
        let dt = lastDate.map { now.timeIntervalSince($0) } ?? 0
        lastDate = now
        guard dt > 0, dt < 1.0 else { return }

        if !connected {
            frozen = true
            return
        }
        frozen = false
        elapsed += dt

        // 玩家速度（踏频驱动）
        let cad = max(0, cadence ?? 0)
        var playerSpeed = cad * cadenceToSpeed

        // 功率基线（EMA）与冲刺检测
        let pw = Double(power ?? 0)
        if powerBaseline == 0 { powerBaseline = pw }
        powerBaseline = powerBaseline * 0.9 + pw * 0.1

        if cooldownTimer > 0 { cooldownTimer -= dt }
        if boostActive {
            boostTimer -= dt
            if boostTimer <= 0 {
                boostActive = false
                cooldownTimer = boostCooldown
            }
        }

        let surge = pw > surgeMinPower &&
                    powerBaseline > surgeMinBaseline &&
                    pw > powerBaseline * surgeRatio &&
                    cooldownTimer <= 0 && !boostActive
        if surge {
            boostActive = true
            boostTimer = boostDuration
        }
        if boostActive { playerSpeed *= boostMultiplier }

        playerDistance += playerSpeed * dt
        aiDistance += aiSpeed * dt
        boostCooldownRemaining = max(0, cooldownTimer)

        // 结束判定
        if playerDistance >= raceDistance || aiDistance >= raceDistance {
            playerDistance = min(playerDistance, raceDistance)
            aiDistance = min(aiDistance, raceDistance)
            state = .finished
            if aiDistance >= raceDistance && playerDistance < raceDistance {
                winner = .ai
            } else {
                winner = .player
                if bestWinTime == 0 || elapsed < bestWinTime {
                    bestWinTime = elapsed
                    UserDefaults.standard.set(bestWinTime, forKey: "ftms_best_win_time")
                }
            }
        }
    }
}

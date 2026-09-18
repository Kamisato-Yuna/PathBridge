import Foundation
import Observation
import PathBridgeCore

@MainActor @Observable
final class UpdateChecker {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates")
            if automaticallyChecks { Task { await checkIfDue() } }
        }
    }
    private(set) var isChecking = false
    private(set) var available: ReleaseUpdate?
    private(set) var message = "尚未检查更新"
    private(set) var lastChecked: Date?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyChecks = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
        lastChecked = defaults.object(forKey: "lastUpdateCheck") as? Date
        backgroundTask = Task { [weak self] in
            // 启动无需打开菜单或设置窗口即可开始检查。
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            while !Task.isCancelled {
                await self?.checkIfDue()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    deinit { backgroundTask?.cancel() }

    private func checkIfDue() async {
        guard automaticallyChecks else { return }
        let previous = defaults.object(forKey: "lastUpdateAttempt") as? Date ?? .distantPast
        guard Date().timeIntervalSince(previous) >= 86400 else { return }
        await check(automatic: true)
    }

    func check(automatic: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defaults.set(Date(), forKey: "lastUpdateAttempt")
        defer { isChecking = false }
        do {
            let update = try await ReleaseUpdate.check(currentVersion: Self.currentVersion)
            guard !automatic || automaticallyChecks else { return }
            available = update
            lastChecked = Date()
            defaults.set(lastChecked, forKey: "lastUpdateCheck")
            message = update.map { "发现新版本 \($0.version)" } ?? "暂无更新的正式版本"
        } catch {
            guard !automatic || automaticallyChecks else { return }
            message = "检查失败：\(error.localizedDescription)"
        }
    }
}

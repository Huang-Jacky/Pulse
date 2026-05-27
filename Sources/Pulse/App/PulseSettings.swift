import Combine
import Foundation
@preconcurrency import ServiceManagement

struct MonitorConfiguration: Sendable, Equatable {
    let enabledCategories: Set<SystemSnapshot.DetailCategory>
    let refreshIntervalSeconds: Int

    func isEnabled(_ category: SystemSnapshot.DetailCategory) -> Bool {
        enabledCategories.contains(category)
    }
}

enum StatusBarDisplayMode: String, CaseIterable, Identifiable {
    case standard
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "标准"
        case .compact:
            return "紧凑"
        }
    }
}

enum StatusBarNetworkDisplayStyle: String, CaseIterable, Identifiable {
    case dualLine
    case singleLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dualLine:
            return "双行"
        case .singleLine:
            return "单行"
        }
    }
}

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
}

@MainActor
final class PulseSettings: ObservableObject {
    private enum Key {
        static let enabledCategories = "pulse.enabledCategories"
        static let refreshIntervalSeconds = "pulse.refreshIntervalSeconds"
        static let legacyRefreshIntervalMinutes = "pulse.refreshIntervalMinutes"
        static let adaptiveRefreshEnabled = "pulse.adaptiveRefreshEnabled"
        static let statusBarOrder = "pulse.statusBarOrder"
        static let statusBarDisplayMode = "pulse.statusBarDisplayMode"
        static let statusBarNetworkDisplayStyle = "pulse.statusBarNetworkDisplayStyle"
    }

    nonisolated static let defaultEnabledCategories = Set(SystemSnapshot.DetailCategory.allCases)
    nonisolated static let orderedCategories = SystemSnapshot.DetailCategory.allCases
    nonisolated static let defaultStatusBarOrder: [SystemSnapshot.DetailCategory] = [.network, .disk, .cpu, .memory]
    nonisolated static let defaultRefreshIntervalSeconds = 1
    nonisolated static let defaultAdaptiveRefreshEnabled = true
    nonisolated static let defaultStatusBarDisplayMode: StatusBarDisplayMode = .standard
    nonisolated static let defaultStatusBarNetworkDisplayStyle: StatusBarNetworkDisplayStyle = .dualLine

    @Published private(set) var enabledCategories: Set<SystemSnapshot.DetailCategory>
    @Published private(set) var statusBarOrder: [SystemSnapshot.DetailCategory]
    @Published private(set) var refreshIntervalSeconds: Int
    @Published private(set) var adaptiveRefreshEnabled: Bool
    @Published private(set) var statusBarDisplayMode: StatusBarDisplayMode
    @Published private(set) var statusBarNetworkDisplayStyle: StatusBarNetworkDisplayStyle
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published private(set) var launchAtLoginErrorMessage: String?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedCategories = Set((userDefaults.array(forKey: Key.enabledCategories) as? [String] ?? []))
        let resolvedCategories = Set(Self.orderedCategories.filter { storedCategories.contains($0.rawValue) })
        enabledCategories = resolvedCategories.isEmpty ? Self.defaultEnabledCategories : resolvedCategories
        statusBarOrder = Self.resolveStatusBarOrder(
            from: userDefaults.array(forKey: Key.statusBarOrder) as? [String] ?? []
        )

        if let storedSeconds = userDefaults.object(forKey: Key.refreshIntervalSeconds) as? Int {
            refreshIntervalSeconds = Self.clampRefreshInterval(storedSeconds)
        } else if let legacyMinutes = userDefaults.object(forKey: Key.legacyRefreshIntervalMinutes) as? Int {
            let migratedSeconds = Self.clampRefreshInterval(legacyMinutes)
            refreshIntervalSeconds = migratedSeconds
            userDefaults.set(migratedSeconds, forKey: Key.refreshIntervalSeconds)
            userDefaults.removeObject(forKey: Key.legacyRefreshIntervalMinutes)
        } else {
            refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        }

        if userDefaults.object(forKey: Key.adaptiveRefreshEnabled) != nil {
            adaptiveRefreshEnabled = userDefaults.bool(forKey: Key.adaptiveRefreshEnabled)
        } else {
            adaptiveRefreshEnabled = Self.defaultAdaptiveRefreshEnabled
        }

        if let rawValue = userDefaults.string(forKey: Key.statusBarDisplayMode),
           let displayMode = StatusBarDisplayMode(rawValue: rawValue) {
            statusBarDisplayMode = displayMode
        } else {
            statusBarDisplayMode = Self.defaultStatusBarDisplayMode
        }

        if let rawValue = userDefaults.string(forKey: Key.statusBarNetworkDisplayStyle),
           let displayStyle = StatusBarNetworkDisplayStyle(rawValue: rawValue) {
            statusBarNetworkDisplayStyle = displayStyle
        } else {
            statusBarNetworkDisplayStyle = Self.defaultStatusBarNetworkDisplayStyle
        }

        launchAtLoginStatus = Self.resolveLaunchAtLoginStatus()
        launchAtLoginErrorMessage = nil
    }

    var monitorConfiguration: MonitorConfiguration {
        MonitorConfiguration(
            enabledCategories: enabledCategories,
            refreshIntervalSeconds: refreshIntervalSeconds
        )
    }

    var detailCategories: [SystemSnapshot.DetailCategory] {
        Self.orderedCategories.filter { enabledCategories.contains($0) }
    }

    var statusBarCategories: [SystemSnapshot.DetailCategory] {
        statusBarOrder.filter { enabledCategories.contains($0) }
    }

    var launchesAtLogin: Bool {
        switch launchAtLoginStatus {
        case .enabled, .requiresApproval:
            return true
        case .disabled:
            return false
        }
    }

    var canManageLaunchAtLogin: Bool {
        true
    }

    var launchAtLoginSubtitle: String {
        switch launchAtLoginStatus {
        case .enabled:
            return "登录后自动启动并保持常驻菜单栏"
        case .disabled:
            return "关闭后仅在手动启动应用时运行"
        case .requiresApproval:
            return "已请求启用，仍需在系统设置的登录项里允许"
        }
    }

    var shouldShowLaunchAtLoginApprovalAction: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    func isEnabled(_ category: SystemSnapshot.DetailCategory) -> Bool {
        enabledCategories.contains(category)
    }

    func isLastEnabledCategory(_ category: SystemSnapshot.DetailCategory) -> Bool {
        enabledCategories.count == 1 && enabledCategories.contains(category)
    }

    func setEnabled(_ category: SystemSnapshot.DetailCategory, isEnabled: Bool) {
        var updated = enabledCategories

        if isEnabled {
            updated.insert(category)
        } else {
            guard updated.count > 1 else {
                return
            }
            updated.remove(category)
        }

        guard updated != enabledCategories else {
            return
        }

        enabledCategories = updated
        persistEnabledCategories()
    }

    func setRefreshInterval(seconds: Int) {
        let clamped = Self.clampRefreshInterval(seconds)
        guard refreshIntervalSeconds != clamped else {
            return
        }

        refreshIntervalSeconds = clamped
        userDefaults.set(clamped, forKey: Key.refreshIntervalSeconds)
        userDefaults.removeObject(forKey: Key.legacyRefreshIntervalMinutes)
    }

    func setAdaptiveRefreshEnabled(_ isEnabled: Bool) {
        guard adaptiveRefreshEnabled != isEnabled else {
            return
        }

        adaptiveRefreshEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Key.adaptiveRefreshEnabled)
    }

    func canMoveStatusBarCategory(_ category: SystemSnapshot.DetailCategory, by delta: Int) -> Bool {
        guard let index = statusBarOrder.firstIndex(of: category) else {
            return false
        }

        let destination = index + delta
        return statusBarOrder.indices.contains(destination)
    }

    func moveStatusBarCategory(_ category: SystemSnapshot.DetailCategory, by delta: Int) {
        guard let index = statusBarOrder.firstIndex(of: category) else {
            return
        }

        let destination = index + delta
        guard statusBarOrder.indices.contains(destination) else {
            return
        }

        var updatedOrder = statusBarOrder
        updatedOrder.swapAt(index, destination)
        guard updatedOrder != statusBarOrder else {
            return
        }

        statusBarOrder = updatedOrder
        userDefaults.set(updatedOrder.map(\.rawValue), forKey: Key.statusBarOrder)
    }

    func setStatusBarDisplayMode(_ mode: StatusBarDisplayMode) {
        guard statusBarDisplayMode != mode else {
            return
        }

        statusBarDisplayMode = mode
        userDefaults.set(mode.rawValue, forKey: Key.statusBarDisplayMode)
    }

    func setStatusBarNetworkDisplayStyle(_ style: StatusBarNetworkDisplayStyle) {
        guard statusBarNetworkDisplayStyle != style else {
            return
        }

        statusBarNetworkDisplayStyle = style
        userDefaults.set(style.rawValue, forKey: Key.statusBarNetworkDisplayStyle)
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = Self.resolveLaunchAtLoginStatus()
    }

    func setLaunchAtLogin(isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = error.localizedDescription
        }

        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func persistEnabledCategories() {
        let rawValues = Self.orderedCategories
            .filter { enabledCategories.contains($0) }
            .map(\.rawValue)
        userDefaults.set(rawValues, forKey: Key.enabledCategories)
    }

    private static func clampRefreshInterval(_ seconds: Int) -> Int {
        min(max(seconds, 1), 30)
    }

    private static func resolveStatusBarOrder(from rawValues: [String]) -> [SystemSnapshot.DetailCategory] {
        var resolved = rawValues.compactMap(SystemSnapshot.DetailCategory.init(rawValue:))
        for category in defaultStatusBarOrder where !resolved.contains(category) {
            resolved.append(category)
        }
        return resolved
    }

    private static func resolveLaunchAtLoginStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }
}

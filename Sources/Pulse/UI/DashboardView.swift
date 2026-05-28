import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: PulseSettings
    @State private var selectedTab: DashboardTab = .metric(.cpu)
    @StateObject private var updateViewModel = UpdateViewModel()

    private var availableTabs: [DashboardTab] {
        settings.detailCategories.map(DashboardTab.metric) + [.settings]
    }

    var body: some View {
        let snapshot = monitor.snapshot

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    HeaderAppIconView(size: 22)
                    Text("Pulse")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                Spacer()
            }

            DetailCategorySwitcher(tabs: availableTabs, selectedTab: $selectedTab)

            ScrollView {
                CategoryContentView(
                    snapshot: snapshot,
                    selectedTab: selectedTab,
                    settings: settings,
                    updateViewModel: updateViewModel
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.never)

            Divider()

            HStack {
                Label(AppText.localized("系统资源监控", "System Resource Monitor"), systemImage: "waveform.path.ecg")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(AppText.localized("退出", "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 404)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.14, green: 0.15, blue: 0.19)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .id(settings.appLanguage)
        .onAppear(perform: syncSelectedTab)
        .onChange(of: settings.detailCategories) { _ in
            syncSelectedTab()
        }
    }

    private func syncSelectedTab() {
        guard !availableTabs.contains(selectedTab), let fallbackTab = availableTabs.first else {
            return
        }
        selectedTab = fallbackTab
    }
}

private enum DashboardTab: Hashable, Identifiable {
    case metric(SystemSnapshot.DetailCategory)
    case settings

    var id: String {
        switch self {
        case let .metric(category):
            return category.rawValue
        case .settings:
            return "settings"
        }
    }

    var title: String {
        switch self {
        case let .metric(category):
            return category.title
        case .settings:
            return AppText.localized("配置", "Settings")
        }
    }
}

private struct DetailCategorySwitcher: View {
    let tabs: [DashboardTab]
    @Binding var selectedTab: DashboardTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(DetailCategoryButtonStyle(isSelected: selectedTab == tab))
            }
        }
    }
}

private struct DetailCategoryButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.82))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                    )
            )
    }
}

private struct CategoryContentView: View {
    let snapshot: SystemSnapshot
    let selectedTab: DashboardTab
    @ObservedObject var settings: PulseSettings
    @ObservedObject var updateViewModel: UpdateViewModel

    var body: some View {
        switch selectedTab {
        case let .metric(category):
            switch category {
            case .cpu:
                CPUCategoryView(snapshot: snapshot)
            case .memory:
                MemoryCategoryView(snapshot: snapshot)
            case .disk:
                DiskCategoryView(snapshot: snapshot)
            case .battery:
                BatteryCategoryView(snapshot: snapshot)
            case .network:
                NetworkCategoryView(snapshot: snapshot)
            }
        case .settings:
            SettingsCategoryView(settings: settings, updateViewModel: updateViewModel)
        }
    }
}

private struct SettingsCategoryView: View {
    @ObservedObject var settings: PulseSettings
    @ObservedObject var updateViewModel: UpdateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                SectionCard(title: AppText.localized("显示指标", "Metrics")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(PulseSettings.orderedCategories.enumerated()), id: \.element) { index, category in
                            ToggleSettingRow(
                                title: category.title,
                                subtitle: category.supportsStatusBar ? AppText.localized("状态栏和详情页同时显示", "Shown in both the menu bar and details") : AppText.localized("仅在详情页显示", "Shown only in the details view"),
                                isOn: settings.isEnabled(category),
                                isToggleEnabled: !settings.isLastEnabledCategory(category),
                                disabledSubtitle: AppText.localized("当前仅剩这一项已启用", "This is the only enabled metric"),
                                isLast: index == PulseSettings.orderedCategories.count - 1
                            ) { isEnabled in
                                settings.setEnabled(category, isEnabled: isEnabled)
                            }
                        }

                        Text(AppText.localized("至少保留 1 个指标。关闭后会从详情标签移除，支持菜单栏的指标也会同步隐藏。", "Keep at least one metric enabled. Disabling it removes its detail tab and also hides it from the menu bar when supported."))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

                SectionCard(title: AppText.localized("菜单栏显示", "Menu Bar")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppText.localized("仅影响菜单栏展示顺序和样式。", "Only affects the menu bar order and appearance."))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(settings.statusBarOrder.enumerated()), id: \.element) { index, category in
                                StatusBarOrderRow(
                                    title: category.title,
                                    isEnabled: settings.isEnabled(category),
                                    canMoveUp: index > 0,
                                    canMoveDown: index < settings.statusBarOrder.count - 1,
                                    isLast: index == settings.statusBarOrder.count - 1,
                                    moveUp: { settings.moveStatusBarCategory(category, by: -1) },
                                    moveDown: { settings.moveStatusBarCategory(category, by: 1) }
                                )
                            }
                        }

                        PickerSettingRow(title: AppText.localized("展示样式", "Display Style")) {
                            Picker(
                                AppText.localized("展示样式", "Display Style"),
                                selection: Binding(
                                    get: { settings.statusBarDisplayMode },
                                    set: { settings.setStatusBarDisplayMode($0) }
                                )
                            ) {
                                ForEach(StatusBarDisplayMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 108)
                        }

                        PickerSettingRow(title: AppText.localized("网络显示", "Network Layout")) {
                            Picker(
                                AppText.localized("网络显示", "Network Layout"),
                                selection: Binding(
                                    get: { settings.statusBarNetworkDisplayStyle },
                                    set: { settings.setStatusBarNetworkDisplayStyle($0) }
                                )
                            ) {
                                ForEach(StatusBarNetworkDisplayStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 108)
                        }

                        Text(AppText.localized("宽度不足时会自动切换到更紧凑的布局。", "Automatically switches to a tighter layout when width is limited."))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard(title: AppText.localized("语言", "Language")) {
                    PickerSettingRow(title: AppText.localized("界面语言", "Interface Language")) {
                        Picker(
                            AppText.localized("界面语言", "Interface Language"),
                            selection: Binding(
                                get: { settings.appLanguage },
                                set: { settings.setAppLanguage($0) }
                            )
                        ) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.optionTitle).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 108)
                    }
                }

                SectionCard(title: AppText.localized("启动", "Launch")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ToggleSettingRow(
                            title: AppText.localized("随系统启动", "Launch at Login"),
                            subtitle: settings.launchAtLoginSubtitle,
                            isOn: settings.launchesAtLogin,
                            isToggleEnabled: settings.canManageLaunchAtLogin,
                            disabledSubtitle: nil,
                            isLast: true
                        ) { isEnabled in
                            settings.setLaunchAtLogin(isEnabled: isEnabled)
                        }

                        if settings.shouldShowLaunchAtLoginApprovalAction {
                            Button(AppText.localized("打开系统设置中的登录项", "Open Login Items in System Settings")) {
                                settings.openLoginItemsSettings()
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }

                        if let launchAtLoginErrorMessage = settings.launchAtLoginErrorMessage,
                           !launchAtLoginErrorMessage.isEmpty {
                            Text("\(AppText.localized("操作失败", "Action failed")): \(launchAtLoginErrorMessage)")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.pink)
                        }
                    }
                }

                SectionCard(title: AppText.localized("采集间隔", "Sampling Interval")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppText.localized("刷新频率", "Refresh Rate"))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text(AppText.localized("1 到 30 秒，采样间隔时间越长更新越慢。", "1 to 30 seconds. Longer intervals refresh more slowly."))
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker(
                            AppText.localized("采集间隔", "Sampling Interval"),
                            selection: Binding(
                                get: { settings.refreshIntervalSeconds },
                                set: { settings.setRefreshInterval(seconds: $0) }
                            )
                        ) {
                            ForEach(1 ... 30, id: \.self) { second in
                                Text(AppText.localized("\(second) 秒", "\(second) s")).tag(second)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 108)
                    }
                }

                SectionCard(title: AppText.localized("刷新策略", "Refresh Strategy")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ToggleSettingRow(
                            title: AppText.localized("智能节能", "Adaptive Power Saving"),
                            subtitle: AppText.localized("系统处于低电量模式时自动降低采集频率。", "Automatically lowers the sampling frequency while the system is in Low Power Mode."),
                            isOn: settings.adaptiveRefreshEnabled,
                            isToggleEnabled: true,
                            disabledSubtitle: nil,
                            isLast: true
                        ) { isEnabled in
                            settings.setAdaptiveRefreshEnabled(isEnabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppMetadata.versionDescription)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        Text("Copyright © 2026 jackey.huang")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    }

                    Spacer(minLength: 10)

                    Button(updateButtonTitle) {
                        updateViewModel.checkForUpdates()
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .disabled(isCheckingForUpdates)
                }

                if let message = updateStatusMessage {
                    HStack(alignment: .center, spacing: 8) {
                        if isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                                .tint(updateStatusColor)
                        } else {
                            Image(systemName: updateStatusIcon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(updateStatusColor)
                        }

                        Text(message)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(updateStatusColor)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        if case .updateAvailable = updateViewModel.status {
                            Button(AppText.localized("前往下载", "Download")) {
                                updateViewModel.openLatestReleasePage()
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(updateStatusBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(updateStatusBorderColor, lineWidth: 1)
                            )
                    )
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 436, alignment: .topLeading)
        .onAppear(perform: settings.refreshLaunchAtLoginStatus)
    }

    private var isCheckingForUpdates: Bool {
        if case .checking = updateViewModel.status {
            return true
        }
        return false
    }

    private var updateButtonTitle: String {
        isCheckingForUpdates ? AppText.localized("检查中...", "Checking...") : AppText.localized("检查更新", "Check for Updates")
    }

    private var updateStatusMessage: String? {
        switch updateViewModel.status {
        case .idle:
            return nil
        case .checking:
            return AppText.localized("正在检查最新版本...", "Checking the latest version...")
        case let .upToDate(version):
            return AppText.localized("当前已是最新版本 \(version)。", "You're already on the latest version \(version).")
        case let .updateAvailable(version, _):
            return AppText.localized("发现新版本 \(version)。", "New version \(version) is available.")
        case let .aheadOfRelease(currentVersion, releaseVersion):
            return AppText.localized("当前版本 \(currentVersion)，正式版最新为 \(releaseVersion)。", "Current version \(currentVersion); latest public release is \(releaseVersion).")
        case let .failed(message):
            return message
        case .unconfigured:
            return AppText.localized("更新源未配置，待 GitHub Releases 准备后启用。", "Update source is not configured yet. Enable it after GitHub Releases is ready.")
        }
    }

    private var updateStatusIcon: String {
        switch updateViewModel.status {
        case .idle, .checking:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "arrow.down.circle.fill"
        case .aheadOfRelease:
            return "info.circle.fill"
        case .failed, .unconfigured:
            return "exclamationmark.triangle.fill"
        }
    }

    private var updateStatusColor: Color {
        switch updateViewModel.status {
        case .upToDate:
            return Palette.green
        case .aheadOfRelease:
            return Palette.blue
        case .failed:
            return Palette.critical
        case .updateAvailable:
            return Palette.warning
        default:
            return .secondary
        }
    }

    private var updateStatusBackgroundColor: Color {
        switch updateViewModel.status {
        case .upToDate:
            return Palette.green.opacity(0.14)
        case .aheadOfRelease:
            return Palette.blue.opacity(0.14)
        case .failed:
            return Palette.critical.opacity(0.16)
        case .updateAvailable:
            return Palette.warning.opacity(0.16)
        case .checking:
            return Color.white.opacity(0.08)
        case .unconfigured:
            return Color.white.opacity(0.06)
        case .idle:
            return .clear
        }
    }

    private var updateStatusBorderColor: Color {
        switch updateViewModel.status {
        case .upToDate, .aheadOfRelease, .failed, .updateAvailable:
            return updateStatusColor.opacity(0.32)
        case .checking:
            return Color.white.opacity(0.12)
        case .unconfigured:
            return Color.white.opacity(0.10)
        case .idle:
            return .clear
        }
    }
}

private struct HeaderAppIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = AppMetadata.headerIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Palette.blue)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ToggleSettingRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let isToggleEnabled: Bool
    let disabledSubtitle: String?
    let isLast: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(isToggleEnabled ? subtitle : (disabledSubtitle ?? subtitle))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        onToggle(newValue)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!isToggleEnabled)
            .frame(width: 52, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isToggleEnabled ? 0.035 : 0.05))
        )
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .offset(y: 4)
            }
        }
    }
}

private struct PickerSettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let control: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Spacer(minLength: 12)
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBarOrderRow: View {
    let title: String
    let isEnabled: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(isEnabled ? AppText.localized("当前会显示在菜单栏", "Currently shown in the menu bar") : AppText.localized("当前已关闭，仅调整顺序", "Currently hidden; order only"))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveUp)
                .opacity(canMoveUp ? 1 : 0.35)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDown)
                .opacity(canMoveDown ? 1 : 0.35)
            }
            .foregroundStyle(Color.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .offset(y: 4)
            }
        }
    }
}

private struct CPUCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let summaryRows = snapshot.detailPanels.cpu.sections[safe: 0]?.rows ?? []
        let processRows = snapshot.detailPanels.cpu.sections[safe: 1]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: "CPU",
                headline: snapshot.cpu.summary,
                trailing: snapshot.cpu.detail,
                accent: Palette.blue,
                symbolName: "cpu",
                headlineColor: Palette.alertTextColor(for: snapshot.cpu.alertLevel)
            ) {
                VStack(spacing: 10) {
                    CPUHistoryChart(history: snapshot.cpuDetails.history)

                    MetricPillGrid(rows: summaryRows)
                }
            }

            SectionCard(title: AppText.localized("核心", "Cores")) {
                CoreUsageGrid(usages: snapshot.cpuDetails.perCoreUsage)
            }

            SectionCard(title: AppText.localized("进程", "Processes")) {
                ProcessList(rows: processRows, valueTitle: "CPU")
            }
        }
    }
}

private struct MemoryCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let vmRows = snapshot.detailPanels.memory.sections[safe: 0]?.rows ?? []
        let processRows = snapshot.detailPanels.memory.sections[safe: 1]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: AppText.localized("内存", "Memory"),
                headline: snapshot.memory.summary,
                trailing: snapshot.memory.detail,
                accent: Palette.green,
                symbolName: "memorychip",
                headlineColor: Palette.alertTextColor(for: snapshot.memory.alertLevel)
            ) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        RingMetricView(
                            value: snapshot.memory.metricValue,
                            label: AppText.localized("内存", "Memory"),
                            subtitle: snapshot.memory.summary,
                            tint: Palette.blue
                        )
                        RingMetricView(
                            value: snapshot.memoryDetails.swapTotal > 0 ? Double(snapshot.memoryDetails.swapUsed) / Double(snapshot.memoryDetails.swapTotal) : 0,
                            label: "Swap",
                            subtitle: snapshot.memoryDetails.swapTotal > 0 ? MetricFormatter.bytes(snapshot.memoryDetails.swapUsed) : "0 B",
                            tint: Palette.pink
                        )
                    }

                    SingleSeriesHistoryChart(
                        values: snapshot.memoryDetails.history,
                        tint: Palette.green
                    )

                    MemoryBreakdownGrid(details: snapshot.memoryDetails)
                    MetricPillGrid(rows: vmRows)
                }
            }

            SectionCard(title: AppText.localized("进程", "Processes")) {
                ProcessList(rows: processRows, valueTitle: AppText.localized("内存", "Memory"))
            }
        }
    }
}

private struct DiskCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let overviewRows = snapshot.detailPanels.disk.sections[safe: 0]?.rows ?? []
        let activityRows = snapshot.detailPanels.disk.sections[safe: 1]?.rows ?? []
        let volumeRows = snapshot.detailPanels.disk.sections[safe: 2]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: AppText.localized("磁盘", "Disk"),
                headline: snapshot.disk.summary,
                trailing: snapshot.disk.detail,
                accent: Palette.blue,
                symbolName: "internaldrive",
                headlineColor: Palette.alertTextColor(for: snapshot.disk.alertLevel)
            ) {
                HStack(spacing: 10) {
                    RingMetricView(
                        value: snapshot.disk.metricValue,
                        label: "SSD",
                        subtitle: snapshot.disk.summary,
                        tint: Palette.blue
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(overviewRows) { row in
                            InlineStatRow(row: row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    NetworkStatCard(
                        title: AppText.localized("读取", "Read"),
                        symbolName: "arrow.down.circle.fill",
                        value: MetricFormatter.bytesPerSecond(snapshot.diskDetails.readRate),
                        tint: Palette.blue
                    )
                    NetworkStatCard(
                        title: AppText.localized("写入", "Write"),
                        symbolName: "arrow.up.circle.fill",
                        value: MetricFormatter.bytesPerSecond(snapshot.diskDetails.writeRate),
                        tint: Palette.pink
                    )
                }

                DiskHistoryChart(history: snapshot.diskDetails.history)
            }

            SectionCard(title: AppText.localized("累计", "Totals")) {
                DetailRowList(rows: Array(activityRows.dropFirst(2)))
            }

            SectionCard(title: AppText.localized("卷", "Volumes")) {
                ProcessList(rows: volumeRows, valueTitle: AppText.localized("已用", "Used"))
            }
        }
    }
}

private struct BatteryCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let healthRows = snapshot.detailPanels.battery.sections[safe: 0]?.rows ?? []
        let powerRows = snapshot.detailPanels.battery.sections[safe: 1]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: AppText.localized("电池", "Battery"),
                headline: snapshot.battery?.summary ?? "--",
                trailing: snapshot.battery?.detail ?? AppText.localized("当前设备未检测到内置电池", "No built-in battery detected on this device"),
                accent: Palette.green,
                symbolName: snapshot.battery?.icon
            ) {
                HStack {
                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        RingMetricView(
                            value: snapshot.battery?.level ?? 0,
                            label: AppText.localized("电量", "Charge"),
                            subtitle: snapshot.battery?.summary ?? "--",
                            tint: Palette.green
                        )
                        RingMetricView(
                            value: snapshot.batteryDetails?.healthRatio ?? 0,
                            label: AppText.localized("健康", "Health"),
                            subtitle: snapshot.batteryDetails?.healthRatio.map(MetricFormatter.percent) ?? "--",
                            tint: Palette.blue
                        )
                    }

                    Spacer(minLength: 0)
                }

                MetricPillGrid(rows: healthRows)
            }

            SectionCard(title: AppText.localized("供电", "Power")) {
                DetailRowList(rows: powerRows)
            }
        }
    }
}

private struct NetworkCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let connectionRows = snapshot.detailPanels.network.sections[safe: 0]?.rows ?? []
        let interfaceRows = snapshot.detailPanels.network.sections[safe: 1]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: AppText.localized("网络", "Network"),
                headline: snapshot.network.download,
                trailing: AppText.localized("下载 · 上传 \(snapshot.network.upload)", "Download · Upload \(snapshot.network.upload)"),
                accent: Palette.pink,
                symbolName: "network"
            ) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        NetworkStatCard(
                            title: AppText.localized("上传", "Upload"),
                            symbolName: "arrow.up.circle.fill",
                            value: snapshot.network.upload,
                            tint: Palette.pink
                        )
                        NetworkStatCard(
                            title: AppText.localized("下载", "Download"),
                            symbolName: "arrow.down.circle.fill",
                            value: snapshot.network.download,
                            tint: Palette.blue
                        )
                    }

                    NetworkHistoryChart(history: snapshot.networkDetails.history)
                }
            }

            SectionCard(title: AppText.localized("当前连接", "Current Connection")) {
                MetricPillGrid(rows: connectionRows)
            }

            SectionCard(title: AppText.localized("接口流量", "Interface Throughput")) {
                ProcessList(rows: interfaceRows, valueTitle: AppText.localized("流量", "Traffic"))
            }
        }
    }
}

private struct HeroCard<Content: View>: View {
    let title: String
    let headline: String
    let trailing: String
    let accent: Color
    var symbolName: String? = nil
    var headlineColor: Color = .white
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    if let symbolName {
                        Image(systemName: symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(headlineColor)
                    Text(trailing)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            content
        }
        .padding(11)
        .background(CardBackground(emphasis: true))
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.blue)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(CardBackground(emphasis: false))
    }
}

private struct CPUHistoryChart: View {
    let history: [SystemSnapshot.CPUHistorySample]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, sample in
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Palette.pink)
                            .frame(height: max(1, geometry.size.height * sample.systemUsage))
                        Rectangle()
                            .fill(Palette.blue)
                            .frame(height: max(1, geometry.size.height * sample.userUsage))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: 66)
    }
}

private struct SingleSeriesHistoryChart: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(height: max(2, geometry.size.height * max(0, min(1, value))))
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: 58)
    }
}

private struct NetworkHistoryChart: View {
    let history: [SystemSnapshot.NetworkHistorySample]

    var body: some View {
        let peak = max(
            history.map { max($0.downloadRate, $0.uploadRate) }.max() ?? 1,
            1
        )

        return GeometryReader { geometry in
            let mid = geometry.size.height / 2
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, sample in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Palette.pink)
                            .frame(height: max(1, mid * sample.uploadRate / peak))
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 2)
                        Rectangle()
                            .fill(Palette.blue)
                            .frame(height: max(1, mid * sample.downloadRate / peak))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: 72)
    }
}

private struct DiskHistoryChart: View {
    let history: [SystemSnapshot.DiskHistorySample]

    var body: some View {
        let peak = max(
            history.map { max($0.readRate, $0.writeRate) }.max() ?? 1,
            1
        )

        return GeometryReader { geometry in
            let mid = geometry.size.height / 2
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, sample in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Palette.pink)
                            .frame(height: max(1, mid * sample.writeRate / peak))
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 2)
                        Rectangle()
                            .fill(Palette.blue)
                            .frame(height: max(1, mid * sample.readRate / peak))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: 60)
    }
}

private struct RingMetricView: View {
    let value: Double
    let label: String
    let subtitle: String
    let tint: Color
    var size: CGFloat = 102
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: size < 90 ? 8.5 : 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.system(size: size < 90 ? 9.5 : 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: size, height: size)
    }
}

private struct CoreUsageGrid: View {
    let usages: [Double]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(usages.enumerated()), id: \.offset) { index, usage in
                VStack(spacing: 4) {
                    RingMetricView(
                        value: usage,
                        label: "C\(index + 1)",
                        subtitle: MetricFormatter.percent(usage),
                        tint: index.isMultiple(of: 2) ? Palette.blue : Palette.pink,
                        size: 64,
                        lineWidth: 5.5
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct MetricPillGrid: View {
    let rows: [SystemSnapshot.DetailRow]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(rows) { row in
                MetricPill(row: row)
            }
        }
    }
}

private struct MetricPill: View {
    let row: SystemSnapshot.DetailRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(row.value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let secondary = row.secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct MemoryBreakdownGrid: View {
    let details: SystemSnapshot.MemoryDetails

    var rows: [SystemSnapshot.DetailRow] {
        [
            .init(label: AppText.localized("活跃", "Active"), value: MetricFormatter.bytes(details.active), secondary: nil),
            .init(label: AppText.localized("有线", "Wired"), value: MetricFormatter.bytes(details.wired), secondary: nil),
            .init(label: AppText.localized("压缩", "Compressed"), value: MetricFormatter.bytes(details.compressed), secondary: nil),
            .init(label: AppText.localized("空闲", "Free"), value: MetricFormatter.bytes(details.free), secondary: nil)
        ]
    }

    var body: some View {
        MetricPillGrid(rows: rows)
    }
}

private struct InlineStatRow: View {
    let row: SystemSnapshot.DetailRow

    var body: some View {
        HStack {
            Text(row.label)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(row.value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }
}

private struct DetailRowList: View {
    let rows: [SystemSnapshot.DetailRow]

    var body: some View {
        VStack(spacing: 8) {
            if rows.isEmpty {
                Text(AppText.localized("暂无数据", "No data"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(rows) { row in
                    InlineStatRow(row: row)
                }
            }
        }
    }
}

private struct NetworkStatCard: View {
    let title: String
    let symbolName: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
            Label(title, systemImage: symbolName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

}

private struct ProcessList: View {
    let rows: [SystemSnapshot.DetailRow]
    let valueTitle: String

    var body: some View {
        VStack(spacing: 6) {
            if rows.isEmpty {
                Text(AppText.localized("暂无数据", "No data"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(AppText.localized("名称", "Name"))
                    Spacer()
                    Text(valueTitle)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            if let secondary = row.secondary, !secondary.isEmpty {
                                Text(secondary)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 10)

                        Text(row.value)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

private struct CardBackground: View {
    let emphasis: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(emphasis ? Color.white.opacity(0.10) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(emphasis ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
            )
    }

}

private enum Palette {
    static let blue = Color(red: 0.18, green: 0.52, blue: 0.98)
    static let pink = Color(red: 0.97, green: 0.34, blue: 0.63)
    static let green = Color(red: 0.20, green: 0.76, blue: 0.56)
    static let warning = Color(red: 0.98, green: 0.63, blue: 0.18)
    static let critical = Color(red: 0.96, green: 0.27, blue: 0.21)

    static func alertTextColor(for alertLevel: SystemSnapshot.MetricAlertLevel) -> Color {
        switch alertLevel {
        case .normal:
            return .white
        case .warning:
            return warning
        case .critical:
            return critical
        }
    }
}

enum AppMetadata {
    static let updateRepository = UpdateRepositoryConfiguration(
        owner: "Huang-Jacky",
        repository: "Pulse"
    )

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppText.localized("开发版", "Dev Build")
    }

    static var versionDescription: String {
        let version = currentVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let build, build != version {
            return AppText.localized("版本 \(version) (\(build))", "Version \(version) (\(build))")
        }
        return AppText.localized("版本 \(version)", "Version \(version)")
    }

    static var headerIcon: NSImage? {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: bundlePath)
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}

private extension SystemSnapshot.GaugeMetric {
    var metricValue: Double { value }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}

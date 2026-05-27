import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: PulseSettings
    @State private var selectedTab: DashboardTab = .metric(.cpu)

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
                    settings: settings
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.never)

            Divider()

            HStack {
                if let battery = snapshot.battery {
                    Label("电池 \(battery.summary)", systemImage: battery.icon)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Label("菜单栏监控", systemImage: "waveform.path.ecg")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("退出") {
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
            return "配置"
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
            case .network:
                NetworkCategoryView(snapshot: snapshot)
            }
        case .settings:
            SettingsCategoryView(settings: settings)
        }
    }
}

private struct SettingsCategoryView: View {
    @ObservedObject var settings: PulseSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                SectionCard(title: "显示指标") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(PulseSettings.orderedCategories.enumerated()), id: \.element) { index, category in
                            ToggleSettingRow(
                                title: category.title,
                                subtitle: "状态栏和详情页同时显示",
                                isOn: settings.isEnabled(category),
                                isToggleEnabled: !settings.isLastEnabledCategory(category),
                                disabledSubtitle: "当前仅剩这一项已启用",
                                isLast: index == PulseSettings.orderedCategories.count - 1
                            ) { isEnabled in
                                settings.setEnabled(category, isEnabled: isEnabled)
                            }
                        }

                        Text("至少保留 1 个指标。关闭后会同步从状态栏和详情标签里移除。")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

                SectionCard(title: "菜单栏显示") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("仅影响菜单栏展示顺序和样式。")
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

                        PickerSettingRow(title: "展示样式") {
                            Picker(
                                "展示样式",
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

                        PickerSettingRow(title: "网络显示") {
                            Picker(
                                "网络显示",
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

                        Text("宽度不足时会自动切换到更紧凑的布局。")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard(title: "启动") {
                    VStack(alignment: .leading, spacing: 8) {
                        ToggleSettingRow(
                            title: "随系统启动",
                            subtitle: settings.launchAtLoginSubtitle,
                            isOn: settings.launchesAtLogin,
                            isToggleEnabled: settings.canManageLaunchAtLogin,
                            disabledSubtitle: nil,
                            isLast: true
                        ) { isEnabled in
                            settings.setLaunchAtLogin(isEnabled: isEnabled)
                        }

                        if settings.shouldShowLaunchAtLoginApprovalAction {
                            Button("打开系统设置中的登录项") {
                                settings.openLoginItemsSettings()
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }

                        if let launchAtLoginErrorMessage = settings.launchAtLoginErrorMessage,
                           !launchAtLoginErrorMessage.isEmpty {
                            Text("操作失败：\(launchAtLoginErrorMessage)")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.pink)
                        }
                    }
                }

                SectionCard(title: "采集间隔") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("刷新频率")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text("1 到 30 秒，采样间隔时间越长更新越慢。")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker(
                            "采集间隔",
                            selection: Binding(
                                get: { settings.refreshIntervalSeconds },
                                set: { settings.setRefreshInterval(seconds: $0) }
                            )
                        ) {
                            ForEach(1 ... 30, id: \.self) { second in
                                Text("\(second) 秒").tag(second)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 108)
                    }
                }

                SectionCard(title: "刷新策略") {
                    VStack(alignment: .leading, spacing: 8) {
                        ToggleSettingRow(
                            title: "智能节能",
                            subtitle: "系统处于低电量模式时自动降低采集频率。",
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

            VStack(alignment: .leading, spacing: 4) {
                Text(AppMetadata.versionDescription)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                Text("Copyright © 2026 jackey.huang")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 436, alignment: .topLeading)
        .onAppear(perform: settings.refreshLaunchAtLoginStatus)
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
                Text(isEnabled ? "当前会显示在菜单栏" : "当前已关闭，仅调整顺序")
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
                accent: Palette.blue
            ) {
                VStack(spacing: 10) {
                    CPUHistoryChart(history: snapshot.cpuDetails.history)

                    MetricPillGrid(rows: summaryRows)
                }
            }

            SectionCard(title: "核心") {
                CoreUsageGrid(usages: snapshot.cpuDetails.perCoreUsage)
            }

            SectionCard(title: "进程") {
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
                title: "内存",
                headline: snapshot.memory.summary,
                trailing: snapshot.memory.detail,
                accent: Palette.green
            ) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        RingMetricView(
                            value: snapshot.memory.metricValue,
                            label: "内存",
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

            SectionCard(title: "进程") {
                ProcessList(rows: processRows, valueTitle: "内存")
            }
        }
    }
}

private struct DiskCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let overviewRows = snapshot.detailPanels.disk.sections[safe: 0]?.rows ?? []
        let volumeRows = snapshot.detailPanels.disk.sections[safe: 1]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: "磁盘",
                headline: snapshot.disk.summary,
                trailing: snapshot.disk.detail,
                accent: Palette.blue
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
            }

            SectionCard(title: "卷") {
                ProcessList(rows: volumeRows, valueTitle: "已用")
            }
        }
    }
}

private struct NetworkCategoryView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let addressRows = snapshot.detailPanels.network.sections[safe: 0]?.rows ?? []
        let interfaceRows = snapshot.detailPanels.network.sections[safe: 1]?.rows ?? []

        VStack(alignment: .leading, spacing: 10) {
            HeroCard(
                title: "网络",
                headline: snapshot.network.download,
                trailing: "下载 · 上传 \(snapshot.network.upload)",
                accent: Palette.pink
            ) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        NetworkStatCard(
                            title: "上传",
                            value: snapshot.network.upload,
                            tint: Palette.pink
                        )
                        NetworkStatCard(
                            title: "下载",
                            value: snapshot.network.download,
                            tint: Palette.blue
                        )
                    }

                    NetworkHistoryChart(history: snapshot.networkDetails.history)
                }
            }

            if !addressRows.isEmpty {
                SectionCard(title: "地址") {
                    ProcessList(rows: addressRows, valueTitle: "地址")
                }
            }

            SectionCard(title: "接口") {
                ProcessList(rows: interfaceRows, valueTitle: "流量")
            }
        }
    }
}

private struct HeroCard<Content: View>: View {
    let title: String
    let headline: String
    let trailing: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
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
            .init(label: "活跃", value: MetricFormatter.bytes(details.active), secondary: nil),
            .init(label: "有线", value: MetricFormatter.bytes(details.wired), secondary: nil),
            .init(label: "压缩", value: MetricFormatter.bytes(details.compressed), secondary: nil),
            .init(label: "空闲", value: MetricFormatter.bytes(details.free), secondary: nil)
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

private struct NetworkStatCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
            Label(title, systemImage: title == "上传" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
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
                Text("暂无数据")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text("名称")
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
}

private enum AppMetadata {
    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let build, build != version {
            return "版本 \(version) (\(build))"
        }
        return "版本 \(version)"
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

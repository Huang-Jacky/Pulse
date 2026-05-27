import SwiftUI

private enum MenuBarPalette {
    static let normal = Color.primary
    static let warning = Color(red: 0.98, green: 0.63, blue: 0.18)
    static let critical = Color(red: 0.96, green: 0.27, blue: 0.21)

    static func color(for alertLevel: SystemSnapshot.MetricAlertLevel, normal: Color) -> Color {
        switch alertLevel {
        case .normal:
            return normal
        case .warning:
            return warning
        case .critical:
            return critical
        }
    }
}

struct MenuBarPresentation: Equatable {
    let displayMode: StatusBarDisplayMode
    let networkDisplayStyle: StatusBarNetworkDisplayStyle

    var itemSpacing: CGFloat {
        displayMode == .standard ? 8 : 6
    }

    var horizontalPadding: CGFloat {
        displayMode == .standard ? 3 : 2
    }

    func estimatedWidth(for categories: [SystemSnapshot.DetailCategory]) -> CGFloat {
        let contentWidth = categories.reduce(CGFloat.zero) { partialResult, category in
            partialResult + estimatedItemWidth(for: category)
        }
        let spacingWidth = CGFloat(max(0, categories.count - 1)) * itemSpacing
        return contentWidth + spacingWidth + horizontalPadding * 2
    }

    func estimatedItemWidth(for category: SystemSnapshot.DetailCategory) -> CGFloat {
        switch category {
        case .cpu, .memory, .disk, .battery:
            switch displayMode {
            case .standard:
                return 36
            case .compact:
                return 26
            }
        case .network:
            switch (displayMode, networkDisplayStyle) {
            case (.standard, .dualLine):
                return 62
            case (.standard, .singleLine):
                return 60
            case (.compact, .dualLine):
                return 48
            case (.compact, .singleLine):
                return 46
            }
        }
    }
}

struct MenuBarStatusView: View {
    let snapshot: SystemSnapshot
    @ObservedObject var settings: PulseSettings
    let presentation: MenuBarPresentation

    var body: some View {
        HStack(alignment: .center, spacing: presentation.itemSpacing) {
            ForEach(settings.statusBarCategories, id: \.self) { category in
                switch category {
                case .cpu:
                    StatusBarMetricColumn(
                        title: "CPU",
                        compactTitle: "C",
                        value: snapshot.cpu.summary,
                        alertLevel: snapshot.cpu.alertLevel,
                        normalColor: MenuBarPalette.normal,
                        mode: presentation.displayMode
                    )
                case .memory:
                    StatusBarMetricColumn(
                        title: "MEM",
                        compactTitle: "M",
                        value: snapshot.memory.summary,
                        alertLevel: snapshot.memory.alertLevel,
                        normalColor: MenuBarPalette.normal,
                        mode: presentation.displayMode
                    )
                case .disk:
                    StatusBarMetricColumn(
                        title: "SSD",
                        compactTitle: "D",
                        value: snapshot.disk.summary,
                        alertLevel: snapshot.disk.alertLevel,
                        normalColor: MenuBarPalette.normal,
                        mode: presentation.displayMode
                    )
                case .battery:
                    StatusBarMetricColumn(
                        title: "BAT",
                        compactTitle: "B",
                        value: snapshot.battery?.summary ?? "--",
                        alertLevel: .normal,
                        normalColor: MenuBarPalette.normal,
                        mode: presentation.displayMode
                    )
                case .network:
                    NetworkStatusBarColumn(
                        upload: snapshot.network.statusBarUploadLine,
                        download: snapshot.network.statusBarDownloadLine,
                        compactSummary: snapshot.network.compactSummary,
                        mode: presentation.displayMode,
                        style: presentation.networkDisplayStyle
                    )
                }
            }
        }
        .padding(.horizontal, presentation.horizontalPadding)
        .padding(.vertical, 1)
        .fixedSize(horizontal: true, vertical: false)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let labels = settings.statusBarCategories.compactMap { category -> String? in
            switch category {
            case .cpu:
                return "CPU \(snapshot.cpu.summary)"
            case .memory:
                return "内存 \(snapshot.memory.summary)"
            case .disk:
                return "磁盘 \(snapshot.disk.summary)"
            case .battery:
                return "电池 \(snapshot.battery?.summary ?? "--")"
            case .network:
                return "网络下行 \(snapshot.network.download)，上行 \(snapshot.network.upload)"
            }
        }

        return labels.isEmpty ? "Pulse 未启用监控指标" : labels.joined(separator: "，")
    }
}

private struct StatusBarMetricColumn: View {
    let title: String
    let compactTitle: String
    let value: String
    let alertLevel: SystemSnapshot.MetricAlertLevel
    let normalColor: Color
    let mode: StatusBarDisplayMode

    var body: some View {
        switch mode {
        case .standard:
            VStack(alignment: .leading, spacing: -1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text(value)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(alertColor)
                    .frame(width: 36, alignment: .leading)
            }
        case .compact:
            VStack(alignment: .leading, spacing: -1) {
                Text(compactTitle)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(alertColor)
            }
            .frame(width: 26, alignment: .leading)
        }
    }

    private var alertColor: Color {
        MenuBarPalette.color(for: alertLevel, normal: normalColor)
    }
}

private struct NetworkStatusBarColumn: View {
    let upload: String
    let download: String
    let compactSummary: String
    let mode: StatusBarDisplayMode
    let style: StatusBarNetworkDisplayStyle

    var body: some View {
        switch style {
        case .dualLine:
            VStack(alignment: .leading, spacing: mode == .standard ? -1 : 0) {
                NetworkFlowRow(symbol: "arrow.up", value: upload, mode: mode)
                NetworkFlowRow(symbol: "arrow.down", value: download, mode: mode)
            }
        case .singleLine:
            VStack(alignment: .leading, spacing: -1) {
                Text(mode == .standard ? "NET" : "N")
                    .font(.system(size: mode == .standard ? 8.5 : 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(compactSummary)
                    .font(.system(size: mode == .standard ? 10.5 : 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: mode == .standard ? 60 : 46, alignment: .leading)
        }
    }
}

private struct NetworkFlowRow: View {
    let symbol: String
    let value: String
    let mode: StatusBarDisplayMode

    var body: some View {
        HStack(spacing: mode == .standard ? 2 : 1) {
            Image(systemName: symbol)
                .font(.system(size: mode == .standard ? 9 : 8, weight: .bold))
                .frame(width: mode == .standard ? 8 : 7)
            Text(value)
                .font(.system(size: mode == .standard ? 10 : 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: mode == .standard ? 52 : 40, alignment: .leading)
        }
    }
}

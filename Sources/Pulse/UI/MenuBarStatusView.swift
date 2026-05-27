import SwiftUI

struct MenuBarStatusView: View {
    let snapshot: SystemSnapshot
    @ObservedObject var settings: PulseSettings

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(settings.statusBarCategories, id: \.self) { category in
                switch category {
                case .cpu:
                    StatusBarMetricColumn(title: "CPU", value: snapshot.cpu.summary, width: 36)
                case .memory:
                    StatusBarMetricColumn(title: "MEM", value: snapshot.memory.summary, width: 36)
                case .disk:
                    StatusBarMetricColumn(title: "SSD", value: snapshot.disk.summary, width: 36)
                case .network:
                    NetworkStatusBarColumn(
                        upload: snapshot.network.statusBarUploadLine,
                        download: snapshot.network.statusBarDownloadLine
                    )
                }
            }
        }
        .padding(.horizontal, 3)
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
            case .network:
                return "网络下行 \(snapshot.network.download)，上行 \(snapshot.network.upload)"
            }
        }

        return labels.isEmpty ? "Pulse 未启用监控指标" : labels.joined(separator: "，")
    }
}

private struct StatusBarMetricColumn: View {
    let title: String
    let value: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(title)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

private struct NetworkStatusBarColumn: View {
    let upload: String
    let download: String

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            NetworkFlowRow(symbol: "arrow.up", value: upload)
            NetworkFlowRow(symbol: "arrow.down", value: download)
        }
    }
}

private struct NetworkFlowRow: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 8)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 52, alignment: .leading)
        }
    }
}

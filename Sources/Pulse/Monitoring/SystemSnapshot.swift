import Foundation

struct SystemSnapshot: Sendable {
    enum MetricAlertLevel: Sendable {
        case normal
        case warning
        case critical
    }

    enum DetailCategory: String, CaseIterable, Identifiable, Sendable {
        case cpu
        case memory
        case disk
        case battery
        case network

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu:
                return "CPU"
            case .memory:
                return "内存"
            case .disk:
                return "磁盘"
            case .battery:
                return "电池"
            case .network:
                return "网络"
            }
        }

        var supportsStatusBar: Bool {
            switch self {
            case .battery:
                return false
            case .cpu, .memory, .disk, .network:
                return true
            }
        }
    }

    struct GaugeMetric: Identifiable, Sendable {
        let id = UUID()
        let category: DetailCategory
        let title: String
        let value: Double
        let summary: String
        let detail: String
        let accent: String
        let alertLevel: MetricAlertLevel
    }

    struct NetworkMetric: Sendable {
        let download: String
        let upload: String
        let totalReceived: String
        let totalSent: String
        let compactSummary: String
        let statusBarDownloadLine: String
        let statusBarUploadLine: String
    }

    struct BatteryMetric: Sendable {
        let level: Double
        let summary: String
        let detail: String
        let icon: String
    }

    struct CPUHistorySample: Sendable {
        let userUsage: Double
        let systemUsage: Double
    }

    struct CPUDetails: Sendable {
        let userUsage: Double
        let systemUsage: Double
        let niceUsage: Double
        let idleUsage: Double
        let perCoreUsage: [Double]
        let loadAverages: [Double]
        let uptime: String
        let history: [CPUHistorySample]
    }

    struct MemoryDetails: Sendable {
        let used: UInt64
        let total: UInt64
        let active: UInt64
        let wired: UInt64
        let compressed: UInt64
        let free: UInt64
        let inactive: UInt64
        let swapUsed: UInt64
        let swapTotal: UInt64
        let pageInCount: UInt64
        let pageOutCount: UInt64
        let pressureLevel: MetricAlertLevel
        let pressureSummary: String
        let history: [Double]
    }

    struct DiskHistorySample: Sendable {
        let readRate: Double
        let writeRate: Double
    }

    struct DiskDetails: Sendable {
        let readRate: Double
        let writeRate: Double
        let totalRead: UInt64
        let totalWrite: UInt64
        let history: [DiskHistorySample]
    }

    struct NetworkAddress: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let address: String
        let interface: String
    }

    struct NetworkHistorySample: Sendable {
        let downloadRate: Double
        let uploadRate: Double
    }

    struct NetworkDetails: Sendable {
        let wifi: WiFiDetails?
        let addresses: [NetworkAddress]
        let history: [NetworkHistorySample]
    }

    struct WiFiDetails: Sendable {
        let status: String
        let detail: String
        let interfaceName: String
        let networkName: String?
        let authorizationNote: String?
        let standard: String?
        let channel: String?
        let transmitRateMbps: Int?
        let rssi: Int?
        let noise: Int?
        let quality: Double?
    }

    struct BatteryDetails: Sendable {
        let healthRatio: Double?
        let cycleCount: Int?
        let designCapacity: UInt64?
        let fullChargeCapacity: UInt64?
        let temperatureCelsius: Double?
        let adapterPowerWatts: Int?
    }

    struct DetailRow: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let value: String
        let secondary: String?
    }

    struct DetailSection: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let rows: [DetailRow]
    }

    struct DetailPanel: Sendable {
        let title: String
        let subtitle: String
        let sections: [DetailSection]
    }

    struct DetailPanels: Sendable {
        let cpu: DetailPanel
        let memory: DetailPanel
        let disk: DetailPanel
        let battery: DetailPanel
        let network: DetailPanel

        func panel(for category: DetailCategory) -> DetailPanel {
            switch category {
            case .cpu:
                return cpu
            case .memory:
                return memory
            case .disk:
                return disk
            case .battery:
                return battery
            case .network:
                return network
            }
        }
    }

    let cpu: GaugeMetric
    let memory: GaugeMetric
    let disk: GaugeMetric
    let battery: BatteryMetric?
    let network: NetworkMetric
    let cpuDetails: CPUDetails
    let memoryDetails: MemoryDetails
    let diskDetails: DiskDetails
    let batteryDetails: BatteryDetails?
    let networkDetails: NetworkDetails
    let detailPanels: DetailPanels

    var primaryMetrics: [GaugeMetric] {
        [cpu, memory, disk]
    }

    static let placeholder = SystemSnapshot(
        cpu: GaugeMetric(
            category: .cpu,
            title: "CPU",
            value: 0,
            summary: "--",
            detail: "等待采样",
            accent: "cpu",
            alertLevel: .normal
        ),
        memory: GaugeMetric(
            category: .memory,
            title: "内存",
            value: 0,
            summary: "--",
            detail: "等待采样",
            accent: "memory",
            alertLevel: .normal
        ),
        disk: GaugeMetric(
            category: .disk,
            title: "磁盘",
            value: 0,
            summary: "--",
            detail: "等待采样",
            accent: "disk",
            alertLevel: .normal
        ),
        battery: nil,
        network: NetworkMetric(
            download: "--",
            upload: "--",
            totalReceived: "--",
            totalSent: "--",
            compactSummary: "--/--",
            statusBarDownloadLine: "-- KB/s",
            statusBarUploadLine: "-- KB/s"
        ),
        cpuDetails: CPUDetails(
            userUsage: 0,
            systemUsage: 0,
            niceUsage: 0,
            idleUsage: 1,
            perCoreUsage: [],
            loadAverages: [0, 0, 0],
            uptime: "--",
            history: []
        ),
        memoryDetails: MemoryDetails(
            used: 0,
            total: 0,
            active: 0,
            wired: 0,
            compressed: 0,
            free: 0,
            inactive: 0,
            swapUsed: 0,
            swapTotal: 0,
            pageInCount: 0,
            pageOutCount: 0,
            pressureLevel: .normal,
            pressureSummary: "正常",
            history: []
        ),
        diskDetails: DiskDetails(
            readRate: 0,
            writeRate: 0,
            totalRead: 0,
            totalWrite: 0,
            history: []
        ),
        batteryDetails: nil,
        networkDetails: NetworkDetails(
            wifi: nil,
            addresses: [],
            history: []
        ),
        detailPanels: DetailPanels(
            cpu: DetailPanel(
                title: "CPU 详细数据",
                subtitle: "等待采样",
                sections: []
            ),
            memory: DetailPanel(
                title: "内存 详细数据",
                subtitle: "等待采样",
                sections: []
            ),
            disk: DetailPanel(
                title: "磁盘 详细数据",
                subtitle: "等待采样",
                sections: []
            ),
            battery: DetailPanel(
                title: "电池 详细数据",
                subtitle: "等待采样",
                sections: []
            ),
            network: DetailPanel(
                title: "网络 详细数据",
                subtitle: "等待采样",
                sections: []
            )
        )
    )
}

enum MetricFormatter {
    static func alertLevel(for category: SystemSnapshot.DetailCategory, value: Double) -> SystemSnapshot.MetricAlertLevel {
        switch category {
        case .cpu, .memory:
            if value >= 0.9 {
                return .critical
            }
            if value >= 0.8 {
                return .warning
            }
            return .normal
        case .disk:
            if value >= 0.95 {
                return .critical
            }
            if value >= 0.9 {
                return .warning
            }
            return .normal
        case .battery:
            return .normal
        case .network:
            return .normal
        }
    }

    static func percent(_ value: Double) -> String {
        let clamped = max(0, min(1, value))
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    static func decimalBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func diskBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let (displayValue, unitIndex) = rateComponents(for: value, minimumUnitIndex: 1)
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]

        let formattedValue: String
        if displayValue >= 100 || abs(displayValue.rounded() - displayValue) < 0.05 {
            formattedValue = "\(Int(displayValue.rounded()))"
        } else {
            formattedValue = String(format: "%.1f", displayValue)
        }

        return "\(formattedValue) \(units[unitIndex])"
    }

    static func compactRate(_ value: Double) -> String {
        let (displayValue, unitIndex) = rateComponents(for: value, minimumUnitIndex: 1)
        let units = ["B", "K", "M", "G", "T"]

        let formattedValue: String
        if displayValue >= 10 || abs(displayValue.rounded() - displayValue) < 0.05 {
            formattedValue = "\(Int(displayValue.rounded()))"
        } else {
            formattedValue = String(format: "%.1f", displayValue)
        }

        return "\(formattedValue)\(units[unitIndex])"
    }

    static func statusBarNetworkLine(_ value: Double) -> String {
        let kilobytes = max(0, value) / 1024

        if kilobytes < 1000 {
            return "\(Int(kilobytes.rounded())) KB/s"
        }

        let megabytes = kilobytes / 1024

        if megabytes < 10 {
            return String(format: "%.1f MB/s", megabytes)
        }

        if megabytes < 1000 {
            return "\(Int(megabytes.rounded())) MB/s"
        }

        return "999 MB/s"
    }

    private static func rateComponents(for value: Double, minimumUnitIndex: Int) -> (Double, Int) {
        let unitsCount = 5
        var displayValue = max(0, value)
        var unitIndex = 0

        while displayValue >= 1024, unitIndex < unitsCount - 1 {
            displayValue /= 1024
            unitIndex += 1
        }

        while unitIndex < minimumUnitIndex, unitIndex < unitsCount - 1 {
            displayValue /= 1024
            unitIndex += 1
        }

        return (displayValue, unitIndex)
    }

    static func timeRemaining(minutes: Int) -> String {
        guard minutes >= 0 else {
            return "计算中"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        return "\(remainingMinutes)m"
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)天 \(hours)小时"
        }

        if hours > 0 {
            return "\(hours)小时 \(minutes)分"
        }

        return "\(minutes)分"
    }

    static func compactCount(_ value: UInt64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }

        return "\(value)"
    }

    static func temperature(_ celsius: Double) -> String {
        String(format: "%.1f°C", celsius)
    }

    static func megabitsPerSecond(_ value: Int) -> String {
        "\(value) Mbps"
    }

    static func milliampHours(_ value: UInt64) -> String {
        "\(value) mAh"
    }

    static func memoryPressureSummary(for level: SystemSnapshot.MetricAlertLevel) -> String {
        switch level {
        case .normal:
            return "正常"
        case .warning:
            return "偏高"
        case .critical:
            return "紧张"
        }
    }
}

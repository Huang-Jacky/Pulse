@preconcurrency import Darwin
import AppKit
import Combine
import Foundation
import IOKit.ps

@MainActor
final class SystemMonitor: ObservableObject {
    private struct RefreshPolicy: Equatable {
        enum Mode: Equatable {
            case base
            case dashboardActive
            case batterySaver
            case lowPowerMode

            var description: String {
                switch self {
                case .base:
                    return "按基础采样间隔运行"
                case .dashboardActive:
                    return "面板打开时提升到 1 秒刷新"
                case .batterySaver:
                    return "电池供电时自动放慢刷新"
                case .lowPowerMode:
                    return "低电量模式下自动放慢刷新"
                }
            }
        }

        let intervalSeconds: Int
        let mode: Mode
    }

    @Published private(set) var snapshot = SystemSnapshot.placeholder
    @Published private(set) var effectiveRefreshIntervalSeconds: Int
    @Published private(set) var refreshPolicyDescription: String

    private let settings: PulseSettings
    private var refreshTask: Task<Void, Never>?
    private let sampler = SystemSampler()
    private var settingsCancellables: Set<AnyCancellable> = []
    private var lastRefreshDate: Date?
    private var isDashboardVisible = false

    init(settings: PulseSettings) {
        self.settings = settings
        let initialPolicy = Self.resolveRefreshPolicy(
            baseInterval: settings.refreshIntervalSeconds,
            adaptiveRefreshEnabled: settings.adaptiveRefreshEnabled,
            isDashboardVisible: false,
            isOnBatteryPower: false,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        effectiveRefreshIntervalSeconds = initialPolicy.intervalSeconds
        refreshPolicyDescription = initialPolicy.mode.description
        bindSettings()

        Task {
            await refresh(forceStaticRefresh: true)
        }
        startRefreshTask()
    }

    private func startRefreshTask() {
        refreshTask?.cancel()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    break
                }

                let duration = self.nextRefreshDuration()
                try? await Task.sleep(nanoseconds: duration)

                if Task.isCancelled {
                    break
                }

                await self.refresh()
            }
        }
    }

    private func restartRefreshTask() {
        startRefreshTask()
    }

    private func bindSettings() {
        settings.$refreshIntervalSeconds
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                self.restartRefreshTask()
                Task {
                    await self.refresh(forceStaticRefresh: true)
                }
            }
            .store(in: &settingsCancellables)

        settings.$adaptiveRefreshEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                self.restartRefreshTask()
                Task {
                    await self.refresh(forceStaticRefresh: true)
                }
            }
            .store(in: &settingsCancellables)

        settings.$enabledCategories
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] categories in
                guard let self else {
                    return
                }

                Task {
                    await self.sampler.updateEnabledCategories(categories)
                    await self.refresh(forceStaticRefresh: true)
                }
            }
            .store(in: &settingsCancellables)
    }

    func setDashboardVisible(_ isVisible: Bool) {
        guard isDashboardVisible != isVisible else {
            return
        }

        isDashboardVisible = isVisible
        updateRefreshPolicyState()
        restartRefreshTask()

        if isVisible {
            Task {
                await refresh(forceStaticRefresh: true)
            }
        }
    }

    private func refresh(forceStaticRefresh: Bool = false) async {
        let policy = currentRefreshPolicy()
        updateRefreshPolicyState(policy)
        let now = Date()
        if !forceStaticRefresh,
           let lastRefreshDate,
           now.timeIntervalSince(lastRefreshDate) + 0.05 < TimeInterval(policy.intervalSeconds) {
            return
        }

        lastRefreshDate = now
        snapshot = await sampler.sample(
            configuration: settings.monitorConfiguration,
            forceStaticRefresh: forceStaticRefresh
        )
        updateRefreshPolicyState()
    }

    private func nextRefreshDuration() -> UInt64 {
        let policy = currentRefreshPolicy()
        updateRefreshPolicyState(policy)
        return UInt64(policy.intervalSeconds) * 1_000_000_000
    }

    private func currentRefreshPolicy() -> RefreshPolicy {
        Self.resolveRefreshPolicy(
            baseInterval: settings.refreshIntervalSeconds,
            adaptiveRefreshEnabled: settings.adaptiveRefreshEnabled,
            isDashboardVisible: isDashboardVisible,
            isOnBatteryPower: isRunningOnBatteryPower(),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private func updateRefreshPolicyState(_ policy: RefreshPolicy? = nil) {
        let resolvedPolicy = policy ?? currentRefreshPolicy()
        effectiveRefreshIntervalSeconds = resolvedPolicy.intervalSeconds
        refreshPolicyDescription = resolvedPolicy.mode.description
    }

    private func isRunningOnBatteryPower() -> Bool {
        let powerSourceInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo).takeRetainedValue() as Array

        guard let powerSource = powerSources.first,
              let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any]
        else {
            return false
        }

        let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
        return state == kIOPSBatteryPowerValue
    }

    private static func resolveRefreshPolicy(
        baseInterval: Int,
        adaptiveRefreshEnabled: Bool,
        isDashboardVisible: Bool,
        isOnBatteryPower: Bool,
        isLowPowerModeEnabled: Bool
    ) -> RefreshPolicy {
        guard adaptiveRefreshEnabled else {
            return RefreshPolicy(intervalSeconds: baseInterval, mode: .base)
        }

        if isDashboardVisible {
            return RefreshPolicy(intervalSeconds: 1, mode: .dashboardActive)
        }

        if isLowPowerModeEnabled {
            return RefreshPolicy(intervalSeconds: max(baseInterval, 5), mode: .lowPowerMode)
        }

        if isOnBatteryPower {
            return RefreshPolicy(intervalSeconds: max(baseInterval, 3), mode: .batterySaver)
        }

        return RefreshPolicy(intervalSeconds: baseInterval, mode: .base)
    }
}

private actor SystemSampler {
    private enum SamplingInterval {
        static let historyLimit = 36
    }

    private var cpuSampler = CPUSampler()
    private var networkSampler = NetworkSampler()
    private var cpuHistory: [SystemSnapshot.CPUHistorySample] = []
    private var memoryHistory: [Double] = []
    private var networkHistory: [SystemSnapshot.NetworkHistorySample] = []
    private var enabledCategories = PulseSettings.defaultEnabledCategories

    func updateEnabledCategories(_ categories: Set<SystemSnapshot.DetailCategory>) {
        let disabledCategories = enabledCategories.subtracting(categories)
        enabledCategories = categories

        if disabledCategories.contains(.cpu) {
            cpuHistory.removeAll()
        }

        if disabledCategories.contains(.memory) {
            memoryHistory.removeAll()
        }

        if disabledCategories.contains(.network) {
            networkHistory.removeAll()
            networkSampler.reset()
        }
    }

    func sample(configuration: MonitorConfiguration, forceStaticRefresh _: Bool = false) -> SystemSnapshot {
        enabledCategories = configuration.enabledCategories

        let cpuReading = configuration.isEnabled(.cpu) ? readCPU() : .placeholder
        let memoryReading = configuration.isEnabled(.memory) ? readMemory() : .placeholder
        let diskReading = configuration.isEnabled(.disk) ? readDisk() : .placeholder
        let battery = readBattery()
        let networkReading = configuration.isEnabled(.network) ? readNetwork() : .placeholder

        if configuration.isEnabled(.cpu) {
            appendCPUHistory(user: cpuReading.userUsage, system: cpuReading.systemUsage)
        }

        if configuration.isEnabled(.memory) {
            appendMemoryHistory(usage: memoryReading.metric.value)
        }

        if configuration.isEnabled(.network) {
            appendNetworkHistory(download: networkReading.metricRate.downloadRate, upload: networkReading.metricRate.uploadRate)
        }

        let needsProcessSample = configuration.isEnabled(.cpu) || configuration.isEnabled(.memory)
        let processes = needsProcessSample ? ProcessSampler.sampleProcesses() : []
        let mountedVolumes = configuration.isEnabled(.disk) ? readMountedVolumes() : []
        let networkAddresses = configuration.isEnabled(.network) ? readNetworkAddresses() : []
        let detailPanels = buildDetailPanels(
            configuration: configuration,
            cpu: cpuReading,
            memory: memoryReading,
            disk: diskReading,
            network: networkReading,
            processes: processes,
            mountedVolumes: mountedVolumes,
            networkAddresses: networkAddresses
        )

        return SystemSnapshot(
            cpu: cpuReading.metric,
            memory: memoryReading.metric,
            disk: diskReading.metric,
            battery: battery,
            network: networkReading.metric,
            cpuDetails: SystemSnapshot.CPUDetails(
                userUsage: cpuReading.userUsage,
                systemUsage: cpuReading.systemUsage,
                niceUsage: cpuReading.niceUsage,
                idleUsage: cpuReading.idleUsage,
                perCoreUsage: cpuReading.perCoreUsage,
                loadAverages: cpuReading.loadAverages,
                uptime: cpuReading.uptime,
                history: cpuHistory
            ),
            memoryDetails: SystemSnapshot.MemoryDetails(
                used: memoryReading.used,
                total: memoryReading.total,
                active: memoryReading.active,
                wired: memoryReading.wired,
                compressed: memoryReading.compressed,
                free: memoryReading.free,
                inactive: memoryReading.inactive,
                swapUsed: memoryReading.swapUsed,
                swapTotal: memoryReading.swapTotal,
                pageInCount: memoryReading.pageInCount,
                pageOutCount: memoryReading.pageOutCount,
                history: memoryHistory
            ),
            networkDetails: SystemSnapshot.NetworkDetails(
                addresses: networkAddresses,
                history: networkHistory
            ),
            detailPanels: detailPanels
        )
    }

    private func readCPU() -> CPUReading {
        let reading = cpuSampler.sample()
        return CPUReading(
            metric: .init(
                category: .cpu,
                title: "CPU",
                value: reading.totalUsage,
                summary: MetricFormatter.percent(reading.totalUsage),
                detail: "用户 \(MetricFormatter.percent(reading.userUsage)) · 系统 \(MetricFormatter.percent(reading.systemUsage))",
                accent: "cpu",
                alertLevel: MetricFormatter.alertLevel(for: .cpu, value: reading.totalUsage)
            ),
            userUsage: reading.userUsage,
            systemUsage: reading.systemUsage,
            niceUsage: reading.niceUsage,
            idleUsage: reading.idleUsage,
            perCoreUsage: reading.perCoreUsage,
            loadAverages: readLoadAverages(),
            uptime: MetricFormatter.uptime(ProcessInfo.processInfo.systemUptime)
        )
    }

    private func readMemory() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        let totalMemory = ProcessInfo.processInfo.physicalMemory

        guard result == KERN_SUCCESS else {
            return .failure(
                metric: .init(
                    category: .memory,
                    title: "内存",
                    value: 0,
                    summary: "--",
                    detail: "读取失败",
                    accent: "memory",
                    alertLevel: .normal
                )
            )
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageSizeValue = UInt64(pageSize)

        let active = UInt64(stats.active_count) * pageSizeValue
        let wired = UInt64(stats.wire_count) * pageSizeValue
        let compressed = UInt64(stats.compressor_page_count) * pageSizeValue
        let free = UInt64(stats.free_count) * pageSizeValue
        let inactive = UInt64(stats.inactive_count) * pageSizeValue
        let used = active + wired + compressed
        let ratio = totalMemory > 0 ? Double(used) / Double(totalMemory) : 0
        let swapUsage = readSwapUsage()

        return MemoryReading(
            metric: .init(
                category: .memory,
                title: "内存",
                value: ratio,
                summary: MetricFormatter.percent(ratio),
                detail: "\(MetricFormatter.bytes(used)) / \(MetricFormatter.bytes(totalMemory))",
                accent: "memory",
                alertLevel: MetricFormatter.alertLevel(for: .memory, value: ratio)
            ),
            used: used,
            total: totalMemory,
            active: active,
            wired: wired,
            compressed: compressed,
            free: free,
            inactive: inactive,
            swapUsed: swapUsage.used,
            swapTotal: swapUsage.total,
            pageInCount: UInt64(stats.pageins),
            pageOutCount: UInt64(stats.pageouts)
        )
    }

    private func readDisk() -> DiskReading {
        do {
            let rootVolume = URL(fileURLWithPath: "/", isDirectory: true)
            let resourceValues = try rootVolume.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])

            let total = resourceValues.volumeTotalCapacity.flatMap { capacity in
                capacity >= 0 ? UInt64(capacity) : nil
            }

            let available: UInt64?
            if let importantUsage = resourceValues.volumeAvailableCapacityForImportantUsage,
               importantUsage >= 0 {
                available = UInt64(importantUsage)
            } else if let general = resourceValues.volumeAvailableCapacity, general >= 0 {
                available = UInt64(general)
            } else {
                available = nil
            }

            guard let total, let available else {
                throw CocoaError(.fileReadUnknown)
            }

            let used = total > available ? total - available : 0
            let ratio = total > 0 ? Double(used) / Double(total) : 0

            return DiskReading(
                metric: .init(
                    category: .disk,
                    title: "磁盘",
                    value: ratio,
                    summary: MetricFormatter.percent(ratio),
                    detail: "\(MetricFormatter.diskBytes(used)) / \(MetricFormatter.diskBytes(total))",
                    accent: "disk",
                    alertLevel: MetricFormatter.alertLevel(for: .disk, value: ratio)
                ),
                total: total,
                used: used,
                available: available
            )
        } catch {
            return .failure(
                metric: .init(
                    category: .disk,
                    title: "磁盘",
                    value: 0,
                    summary: "--",
                    detail: "读取失败",
                    accent: "disk",
                    alertLevel: .normal
                )
            )
        }
    }

    private func readBattery() -> SystemSnapshot.BatteryMetric? {
        let powerSourceInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo).takeRetainedValue() as Array

        guard let powerSource = powerSources.first,
              let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 0
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
        let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int ?? -1
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int ?? -1
        let isFullyCharged = max > 0 && current >= max

        let level = max > 0 ? Double(current) / Double(max) : 0

        let detail: String
        if isCharging {
            detail = "充电中 · \(MetricFormatter.timeRemaining(minutes: timeToFull)) 到充满"
        } else if state == kIOPSBatteryPowerValue {
            detail = "电池供电 · \(MetricFormatter.timeRemaining(minutes: timeToEmpty)) 剩余"
        } else {
            detail = "接通电源"
        }

        return .init(
            level: level,
            summary: MetricFormatter.percent(level),
            detail: detail,
            icon: batteryIconName(level: level, isCharging: isCharging, isFullyCharged: isFullyCharged)
        )
    }

    private func batteryIconName(level: Double, isCharging: Bool, isFullyCharged: Bool) -> String {
        let percentage = Int((max(0, min(1, level)) * 100).rounded())
        let candidates: [String]

        if isFullyCharged || percentage >= 100 {
            candidates = isCharging
                ? ["battery.100percent.bolt", "battery.100.bolt", "battery.100percent", "battery.100"]
                : ["battery.100percent", "battery.100"]
        } else if percentage <= 10 {
            candidates = ["battery.0", "battery.25", "battery.25percent"]
        } else if percentage <= 30 {
            candidates = ["battery.25", "battery.25percent", "battery.0"]
        } else if percentage <= 60 {
            candidates = ["battery.50", "battery.50percent", "battery.25"]
        } else {
            candidates = ["battery.75", "battery.75percent", "battery.50"]
        }

        for name in candidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }

        return isCharging ? "bolt.fill" : "battery.100percent"
    }

    private func readNetwork() -> NetworkReading {
        let sample = networkSampler.sample()
        return NetworkReading(
            metric: .init(
                download: MetricFormatter.bytesPerSecond(sample.downloadRate),
                upload: MetricFormatter.bytesPerSecond(sample.uploadRate),
                totalReceived: MetricFormatter.bytes(sample.totalReceived),
                totalSent: MetricFormatter.bytes(sample.totalSent),
                compactSummary: "\(MetricFormatter.compactRate(sample.downloadRate))/\(MetricFormatter.compactRate(sample.uploadRate))",
                statusBarDownloadLine: MetricFormatter.statusBarNetworkLine(sample.downloadRate),
                statusBarUploadLine: MetricFormatter.statusBarNetworkLine(sample.uploadRate)
            ),
            metricRate: .init(downloadRate: sample.downloadRate, uploadRate: sample.uploadRate),
            interfaces: sample.interfaces
        )
    }

    private func appendCPUHistory(user: Double, system: Double) {
        cpuHistory.append(.init(userUsage: user, systemUsage: system))
        if cpuHistory.count > SamplingInterval.historyLimit {
            cpuHistory.removeFirst(cpuHistory.count - SamplingInterval.historyLimit)
        }
    }

    private func appendMemoryHistory(usage: Double) {
        memoryHistory.append(usage)
        if memoryHistory.count > SamplingInterval.historyLimit {
            memoryHistory.removeFirst(memoryHistory.count - SamplingInterval.historyLimit)
        }
    }

    private func appendNetworkHistory(download: Double, upload: Double) {
        networkHistory.append(.init(downloadRate: download, uploadRate: upload))
        if networkHistory.count > SamplingInterval.historyLimit {
            networkHistory.removeFirst(networkHistory.count - SamplingInterval.historyLimit)
        }
    }

    private func readLoadAverages() -> [Double] {
        var averages = [Double](repeating: 0, count: 3)
        let result = getloadavg(&averages, 3)
        guard result == 3 else {
            return [0, 0, 0]
        }
        return averages
    }

    private func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var size = MemoryLayout.size(ofValue: swap)
        let result = withUnsafeMutablePointer(to: &swap) { pointer in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }

        guard result == 0 else {
            return (0, 0)
        }

        return (swap.xsu_used, swap.xsu_total)
    }

    private func readNetworkAddresses() -> [SystemSnapshot.NetworkAddress] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let firstPointer = pointer else {
            return []
        }

        defer {
            freeifaddrs(pointer)
        }

        var rows: [SystemSnapshot.NetworkAddress] = []

        for interface in sequence(first: firstPointer, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)

            guard let address = interface.pointee.ifa_addr,
                  (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0
            else {
                continue
            }

            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let interfaceName = String(cString: interface.pointee.ifa_name)
            let terminatorIndex = hostBuffer.firstIndex(of: 0) ?? hostBuffer.count
            let addressBytes = hostBuffer[..<terminatorIndex].map { UInt8(bitPattern: $0) }
            let addressString = String(decoding: addressBytes, as: UTF8.self)

            if family == AF_INET6, addressString.hasPrefix("fe80") {
                continue
            }

            rows.append(
                .init(
                    name: family == AF_INET ? "IPv4" : "IPv6",
                    address: addressString,
                    interface: interfaceName
                )
            )
        }

        return rows
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.interface < rhs.interface
                }
                return lhs.name < rhs.name
            }
            .prefix(4)
            .map { $0 }
    }

    private func readMountedVolumes() -> [MountedVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: []
        ) ?? []

        return urls.compactMap { url -> MountedVolume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true
            else {
                return nil
            }

            let name = if url.path == "/" {
                "系统卷"
            } else if url.path == "/System/Volumes/Data" {
                "数据卷"
            } else {
                values.volumeName ?? url.lastPathComponent
            }

            let total = values.volumeTotalCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil }
            let available = values.volumeAvailableCapacityForImportantUsage.flatMap { $0 >= 0 ? UInt64($0) : nil }
                ?? values.volumeAvailableCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil }

            guard let total, let available else {
                return nil
            }

            // Hide mounted read-only disk images such as the Pulse installer DMG.
            if url.path.hasPrefix("/Volumes/"),
               values.volumeIsReadOnly == true,
               available == 0 {
                return nil
            }

            let shouldShow = url.path == "/" || url.path == "/System/Volumes/Data" || url.path.hasPrefix("/Volumes/")
            guard shouldShow else {
                return nil
            }

            let used = total > available ? total - available : 0
            return MountedVolume(name: name, path: url.path, used: used, total: total, available: available)
        }
        .sorted { lhs, rhs in
            if lhs.path == "/" { return true }
            if rhs.path == "/" { return false }
            return lhs.used > rhs.used
        }
        .prefix(4)
        .map { $0 }
    }

    private func buildDetailPanels(
        configuration: MonitorConfiguration,
        cpu: CPUReading,
        memory: MemoryReading,
        disk: DiskReading,
        network: NetworkReading,
        processes: [ProcessSnapshot],
        mountedVolumes: [MountedVolume],
        networkAddresses: [SystemSnapshot.NetworkAddress]
    ) -> SystemSnapshot.DetailPanels {
        let cpuTopProcesses = processes
            .sorted { $0.cpu > $1.cpu }
            .prefix(6)
            .map {
                SystemSnapshot.DetailRow(
                    label: $0.command,
                    value: String(format: "%.1f%%", $0.cpu),
                    secondary: "PID \($0.pid)"
                )
            }

        let memoryTopProcesses = processes
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(6)
            .map {
                SystemSnapshot.DetailRow(
                    label: $0.command,
                    value: MetricFormatter.bytes($0.memoryBytes),
                    secondary: String(format: "CPU %.1f%%", $0.cpu)
                )
            }

        let cpuPanel = configuration.isEnabled(.cpu)
            ? SystemSnapshot.DetailPanel(
                title: "CPU",
                subtitle: "处理器状态、负载和进程占用",
                sections: [
                    .init(
                        title: "摘要",
                        rows: [
                            .init(label: "负载 1m", value: String(format: "%.2f", cpu.loadAverages[safe: 0] ?? 0), secondary: nil),
                            .init(label: "负载 5m", value: String(format: "%.2f", cpu.loadAverages[safe: 1] ?? 0), secondary: nil),
                            .init(label: "负载 15m", value: String(format: "%.2f", cpu.loadAverages[safe: 2] ?? 0), secondary: nil),
                            .init(label: "运行时间", value: cpu.uptime, secondary: nil)
                        ]
                    ),
                    .init(title: "进程", rows: Array(cpuTopProcesses))
                ]
            )
            : disabledPanel(title: "CPU")

        let memoryPanel = configuration.isEnabled(.memory)
            ? SystemSnapshot.DetailPanel(
                title: "内存",
                subtitle: "物理内存、交换区和进程占用",
                sections: [
                    .init(
                        title: "虚拟内存",
                        rows: [
                            .init(label: "交换已用", value: MetricFormatter.bytes(memory.swapUsed), secondary: memory.swapTotal > 0 ? "总计 \(MetricFormatter.bytes(memory.swapTotal))" : nil),
                            .init(label: "写入分页", value: MetricFormatter.compactCount(memory.pageOutCount), secondary: nil),
                            .init(label: "读取分页", value: MetricFormatter.compactCount(memory.pageInCount), secondary: nil)
                        ]
                    ),
                    .init(title: "进程", rows: Array(memoryTopProcesses))
                ]
            )
            : disabledPanel(title: "内存")

        let diskRows: [SystemSnapshot.DetailRow]
        if disk.total > 0 {
            diskRows = [
                .init(label: "已用", value: MetricFormatter.diskBytes(disk.used), secondary: disk.metric.summary),
                .init(label: "可用", value: MetricFormatter.diskBytes(disk.available), secondary: nil),
                .init(label: "总量", value: MetricFormatter.diskBytes(disk.total), secondary: nil)
            ]
        } else {
            diskRows = [.init(label: "状态", value: "读取失败", secondary: nil)]
        }

        let volumeRows = mountedVolumes.map {
            SystemSnapshot.DetailRow(
                label: $0.name,
                value: MetricFormatter.diskBytes($0.used),
                secondary: "\(MetricFormatter.diskBytes($0.available)) 可用"
            )
        }

        let diskPanel = configuration.isEnabled(.disk)
            ? SystemSnapshot.DetailPanel(
                title: "磁盘",
                subtitle: "主卷容量和本地卷列表",
                sections: [
                    .init(title: "概览", rows: diskRows),
                    .init(title: "卷", rows: volumeRows)
                ]
            )
            : disabledPanel(title: "磁盘")

        let addressRows = networkAddresses.map {
            SystemSnapshot.DetailRow(
                label: $0.name,
                value: $0.address,
                secondary: $0.interface
            )
        }

        let interfaceRows = network.interfaces
            .sorted { ($0.downloadRate + $0.uploadRate) > ($1.downloadRate + $1.uploadRate) }
            .prefix(6)
            .map {
                SystemSnapshot.DetailRow(
                    label: $0.name,
                    value: "↓ \(MetricFormatter.bytesPerSecond($0.downloadRate))",
                    secondary: "↑ \(MetricFormatter.bytesPerSecond($0.uploadRate))"
                )
            }

        let networkPanel = configuration.isEnabled(.network)
            ? SystemSnapshot.DetailPanel(
                title: "网络",
                subtitle: "地址、实时吞吐和接口列表",
                sections: [
                    .init(title: "地址", rows: addressRows),
                    .init(title: "接口", rows: Array(interfaceRows))
                ]
            )
            : disabledPanel(title: "网络")

        return .init(
            cpu: cpuPanel,
            memory: memoryPanel,
            disk: diskPanel,
            network: networkPanel
        )
    }

    private func disabledPanel(title: String) -> SystemSnapshot.DetailPanel {
        SystemSnapshot.DetailPanel(
            title: title,
            subtitle: "未启用",
            sections: []
        )
    }
}

private struct CPUReading {
    let metric: SystemSnapshot.GaugeMetric
    let userUsage: Double
    let systemUsage: Double
    let niceUsage: Double
    let idleUsage: Double
    let perCoreUsage: [Double]
    let loadAverages: [Double]
    let uptime: String

    static let placeholder = CPUReading(
        metric: SystemSnapshot.placeholder.cpu,
        userUsage: 0,
        systemUsage: 0,
        niceUsage: 0,
        idleUsage: 1,
        perCoreUsage: [],
        loadAverages: [0, 0, 0],
        uptime: "--"
    )
}

private struct MemoryReading {
    let metric: SystemSnapshot.GaugeMetric
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

    static let placeholder = MemoryReading.failure(metric: SystemSnapshot.placeholder.memory)

    static func failure(metric: SystemSnapshot.GaugeMetric) -> MemoryReading {
        MemoryReading(
            metric: metric,
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
            pageOutCount: 0
        )
    }
}

private struct DiskReading {
    let metric: SystemSnapshot.GaugeMetric
    let total: UInt64
    let used: UInt64
    let available: UInt64

    static let placeholder = DiskReading(
        metric: SystemSnapshot.placeholder.disk,
        total: 0,
        used: 0,
        available: 0
    )

    static func failure(metric: SystemSnapshot.GaugeMetric) -> DiskReading {
        DiskReading(metric: metric, total: 0, used: 0, available: 0)
    }
}

private struct NetworkReading {
    struct MetricRate {
        let downloadRate: Double
        let uploadRate: Double
    }

    let metric: SystemSnapshot.NetworkMetric
    let metricRate: MetricRate
    let interfaces: [NetworkSampler.InterfaceRate]

    static let placeholder = NetworkReading(
        metric: SystemSnapshot.placeholder.network,
        metricRate: .init(downloadRate: 0, uploadRate: 0),
        interfaces: []
    )
}

private struct MountedVolume {
    let name: String
    let path: String
    let used: UInt64
    let total: UInt64
    let available: UInt64
}

private struct ProcessSnapshot {
    let pid: Int
    let cpu: Double
    let memoryBytes: UInt64
    let command: String
}

private struct ProcessSampler {
    static func sampleProcesses() -> [ProcessSnapshot] {
        guard let output = CommandRunner.run(
            launchPath: "/bin/ps",
            arguments: ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]
        ) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> ProcessSnapshot? in
                let parts = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
                guard parts.count == 4,
                      let pid = Int(parts[0]),
                      let cpu = Double(parts[1]),
                      let rss = UInt64(parts[2])
                else {
                    return nil
                }

                return ProcessSnapshot(
                    pid: pid,
                    cpu: cpu,
                    memoryBytes: rss * 1024,
                    command: String(parts[3])
                )
            }
    }
}

private struct CommandRunner {
    static func run(launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private struct CPUSampler {
    struct Reading {
        let totalUsage: Double
        let userUsage: Double
        let systemUsage: Double
        let niceUsage: Double
        let idleUsage: Double
        let perCoreUsage: [Double]
    }

    private var previousLoadInfo: [UInt32] = []

    mutating func sample() -> Reading {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return .init(totalUsage: 0, userUsage: 0, systemUsage: 0, niceUsage: 0, idleUsage: 1, perCoreUsage: [])
        }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let currentLoadInfo = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount)).map {
            UInt32(bitPattern: $0)
        }

        defer {
            previousLoadInfo = currentLoadInfo
        }

        guard previousLoadInfo.count == currentLoadInfo.count else {
            return .init(totalUsage: 0, userUsage: 0, systemUsage: 0, niceUsage: 0, idleUsage: 1, perCoreUsage: [])
        }

        var userTicks: UInt64 = 0
        var systemTicks: UInt64 = 0
        var niceTicks: UInt64 = 0
        var idleTicks: UInt64 = 0
        var perCoreUsage: [Double] = []

        for cpuIndex in 0 ..< Int(cpuCount) {
            let offset = cpuIndex * Int(CPU_STATE_MAX)

            let user = UInt64(currentLoadInfo[offset + Int(CPU_STATE_USER)] - previousLoadInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(currentLoadInfo[offset + Int(CPU_STATE_SYSTEM)] - previousLoadInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(currentLoadInfo[offset + Int(CPU_STATE_NICE)] - previousLoadInfo[offset + Int(CPU_STATE_NICE)])
            let idle = UInt64(currentLoadInfo[offset + Int(CPU_STATE_IDLE)] - previousLoadInfo[offset + Int(CPU_STATE_IDLE)])

            userTicks += user
            systemTicks += system
            niceTicks += nice
            idleTicks += idle

            let perCoreTotal = user + system + nice + idle
            if perCoreTotal > 0 {
                perCoreUsage.append(Double(user + system + nice) / Double(perCoreTotal))
            } else {
                perCoreUsage.append(0)
            }
        }

        let totalTicks = userTicks + systemTicks + niceTicks + idleTicks
        guard totalTicks > 0 else {
            return .init(totalUsage: 0, userUsage: 0, systemUsage: 0, niceUsage: 0, idleUsage: 1, perCoreUsage: perCoreUsage)
        }

        let total = Double(totalTicks)
        return .init(
            totalUsage: Double(userTicks + systemTicks + niceTicks) / total,
            userUsage: Double(userTicks) / total,
            systemUsage: Double(systemTicks) / total,
            niceUsage: Double(niceTicks) / total,
            idleUsage: Double(idleTicks) / total,
            perCoreUsage: perCoreUsage
        )
    }
}

private struct NetworkSampler {
    struct InterfaceRate {
        let name: String
        let downloadRate: Double
        let uploadRate: Double
        let totalReceived: UInt64
        let totalSent: UInt64
    }

    private struct InterfaceCounters {
        let received: UInt64
        let sent: UInt64
    }

    private struct Sample {
        let received: UInt64
        let sent: UInt64
        let timestamp: Date
        let interfaces: [String: InterfaceCounters]
    }

    struct Rate {
        let downloadRate: Double
        let uploadRate: Double
        let totalReceived: UInt64
        let totalSent: UInt64
        let interfaces: [InterfaceRate]
    }

    private var previousSample: Sample?

    mutating func reset() {
        previousSample = nil
    }

    mutating func sample() -> Rate {
        let current = currentSample()

        defer {
            previousSample = current
        }

        guard let previousSample else {
            return Rate(
                downloadRate: 0,
                uploadRate: 0,
                totalReceived: current.received,
                totalSent: current.sent,
                interfaces: []
            )
        }

        let timeDelta = current.timestamp.timeIntervalSince(previousSample.timestamp)
        guard timeDelta > 0 else {
            return Rate(
                downloadRate: 0,
                uploadRate: 0,
                totalReceived: current.received,
                totalSent: current.sent,
                interfaces: []
            )
        }

        let receivedDelta = current.received >= previousSample.received ? current.received - previousSample.received : 0
        let sentDelta = current.sent >= previousSample.sent ? current.sent - previousSample.sent : 0

        let interfaceRates = current.interfaces.compactMap { name, counters -> InterfaceRate? in
            guard let previousCounters = previousSample.interfaces[name] else {
                return nil
            }

            let received = counters.received >= previousCounters.received ? counters.received - previousCounters.received : 0
            let sent = counters.sent >= previousCounters.sent ? counters.sent - previousCounters.sent : 0

            return InterfaceRate(
                name: name,
                downloadRate: Double(received) / timeDelta,
                uploadRate: Double(sent) / timeDelta,
                totalReceived: counters.received,
                totalSent: counters.sent
            )
        }

        return Rate(
            downloadRate: Double(receivedDelta) / timeDelta,
            uploadRate: Double(sentDelta) / timeDelta,
            totalReceived: current.received,
            totalSent: current.sent,
            interfaces: interfaceRates
        )
    }

    private func currentSample() -> Sample {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var interfaces: [String: InterfaceCounters] = [:]

        guard getifaddrs(&pointer) == 0, let firstPointer = pointer else {
            return Sample(received: 0, sent: 0, timestamp: Date(), interfaces: [:])
        }

        defer {
            freeifaddrs(pointer)
        }

        for interface in sequence(first: firstPointer, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)

            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0,
                  let data = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            let interfaceReceived = UInt64(data.pointee.ifi_ibytes)
            let interfaceSent = UInt64(data.pointee.ifi_obytes)

            received += interfaceReceived
            sent += interfaceSent
            interfaces[name] = InterfaceCounters(received: interfaceReceived, sent: interfaceSent)
        }

        return Sample(received: received, sent: sent, timestamp: Date(), interfaces: interfaces)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}

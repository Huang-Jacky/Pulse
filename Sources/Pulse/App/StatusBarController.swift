import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let monitor: SystemMonitor
    private let settings: PulseSettings
    private let locationPermissionManager: LocationPermissionManager
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var statusHostingView: NSHostingView<MenuBarStatusView>?
    private var cancellables: Set<AnyCancellable> = []

    init(monitor: SystemMonitor, settings: PulseSettings, locationPermissionManager: LocationPermissionManager) {
        self.monitor = monitor
        self.settings = settings
        self.locationPermissionManager = locationPermissionManager
        super.init()
        configureStatusItem()
        configurePopover()
        bindSnapshot()
        updateStatusView(with: monitor.snapshot)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        let hostingView = NSHostingView(
            rootView: MenuBarStatusView(
                snapshot: monitor.snapshot,
                settings: settings,
                presentation: resolvePresentation()
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        statusHostingView = hostingView
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 404, height: 520)
        popover.contentViewController = NSHostingController(rootView: DashboardView(monitor: monitor, settings: settings))
    }

    private func bindSnapshot() {
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusView(with: snapshot)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            settings.$enabledCategories,
            settings.$statusBarOrder,
            settings.$statusBarDisplayMode,
            settings.$statusBarNetworkDisplayStyle
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                guard let self else {
                    return
                }
                self.updateStatusView(with: self.monitor.snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusView(with snapshot: SystemSnapshot) {
        guard let statusHostingView else {
            return
        }

        let presentation = resolvePresentation()
        statusHostingView.rootView = MenuBarStatusView(
            snapshot: snapshot,
            settings: settings,
            presentation: presentation
        )
        let width = presentation.estimatedWidth(for: settings.statusBarCategories) + 8
        statusItem.length = max(width, NSStatusItem.variableLength)
    }

    private func resolvePresentation() -> MenuBarPresentation {
        let preferred = MenuBarPresentation(
            displayMode: settings.statusBarDisplayMode,
            networkDisplayStyle: settings.statusBarNetworkDisplayStyle
        )
        let categories = settings.statusBarCategories
        let widthBudget = statusItemWidthBudget()
        let candidates = fallbackPresentations(from: preferred)

        for presentation in candidates where presentation.estimatedWidth(for: categories) <= widthBudget {
            return presentation
        }

        return candidates.last ?? preferred
    }

    private func fallbackPresentations(from preferred: MenuBarPresentation) -> [MenuBarPresentation] {
        var candidates: [MenuBarPresentation] = [preferred]

        let compactPreferred = MenuBarPresentation(
            displayMode: .compact,
            networkDisplayStyle: preferred.networkDisplayStyle
        )
        let singleLinePreferred = MenuBarPresentation(
            displayMode: preferred.displayMode,
            networkDisplayStyle: .singleLine
        )
        let mostCompact = MenuBarPresentation(displayMode: .compact, networkDisplayStyle: .singleLine)

        for candidate in [compactPreferred, singleLinePreferred, mostCompact] where !candidates.contains(candidate) {
            candidates.append(candidate)
        }

        return candidates
    }

    private func statusItemWidthBudget() -> CGFloat {
        let screenWidth = statusItem.button?.window?.screen?.visibleFrame.width
            ?? NSScreen.main?.visibleFrame.width
            ?? 1440
        return min(max(screenWidth * 0.14, 170), 230)
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            locationPermissionManager.requestWiFiAccessIfNeeded()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            monitor.setDashboardVisible(true)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        monitor.setDashboardVisible(false)
    }
}

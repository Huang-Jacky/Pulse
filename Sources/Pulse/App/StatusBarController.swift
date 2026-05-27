import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let monitor: SystemMonitor
    private let settings: PulseSettings
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var statusHostingView: NSHostingView<MenuBarStatusView>?
    private var snapshotCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?

    init(monitor: SystemMonitor, settings: PulseSettings) {
        self.monitor = monitor
        self.settings = settings
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

        let hostingView = NSHostingView(rootView: MenuBarStatusView(snapshot: monitor.snapshot, settings: settings))
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
        popover.contentSize = NSSize(width: 404, height: 520)
        popover.contentViewController = NSHostingController(rootView: DashboardView(monitor: monitor, settings: settings))
    }

    private func bindSnapshot() {
        snapshotCancellable = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusView(with: snapshot)
            }

        settingsCancellable = settings.$enabledCategories
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.updateStatusView(with: self.monitor.snapshot)
            }
    }

    private func updateStatusView(with snapshot: SystemSnapshot) {
        guard let statusHostingView else {
            return
        }

        statusHostingView.rootView = MenuBarStatusView(snapshot: snapshot, settings: settings)
        let width = statusHostingView.fittingSize.width + 8
        statusItem.length = max(width, NSStatusItem.variableLength)
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}

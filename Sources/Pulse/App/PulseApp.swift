import AppKit
import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pulse")
                    .font(.title2.bold())
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = PulseSettings()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let monitor = SystemMonitor(settings: settings)
        statusBarController = StatusBarController(monitor: monitor, settings: settings)
    }
}

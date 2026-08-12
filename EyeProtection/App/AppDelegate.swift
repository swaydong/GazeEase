import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        ReminderNotificationService.shared.configure()
        Task { @MainActor in
            AppModel.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isRunningTests else { return }
        MainActor.assumeIsolated {
            AppModel.shared.stop()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

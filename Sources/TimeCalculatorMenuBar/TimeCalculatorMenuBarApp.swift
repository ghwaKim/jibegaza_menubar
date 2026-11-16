import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum TimeCalculatorMenuBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = WeekRolloverPreview.makeViewModel()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !WeekRolloverPreview.isEnabled { AppUpdater.shared.start() }

        let menuBar = MenuBarController(viewModel: viewModel)
        self.menuBar = menuBar
        if WeekRolloverPreview.isEnabled {
            menuBar.show()
            return
        }
        LaunchAtLogin.registerOnFirstLaunch()
        FlexConnection.shared.start(
            onClockIn: { [weak viewModel] date, now in viewModel?.syncFlexClockIn(date, now: now) },
            onImportRecords: { [weak viewModel] records, now, automatic in
                viewModel?.importFlexRecords(records, now: now, automatic: automatic) ?? "주간 기록에 반영할 수 없어요."
            },
            onDisconnect: { [weak viewModel] in viewModel?.clearFlexClockInSource() },
            onLoginFinished: { [weak self] tab in
                guard let self else { return }
                self.viewModel.selectedTab = tab
                self.menuBar?.show()
            })
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func didWake() {
        FlexConnection.shared.syncAfterWake()
    }
}

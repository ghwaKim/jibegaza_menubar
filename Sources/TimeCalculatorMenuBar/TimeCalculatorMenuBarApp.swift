import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TimeCalculatorMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TimeCalculatorViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(viewModel)
                .frame(width: 430)
        } label: {
            (
                Text(viewModel.menuBarEmoji)
                + (viewModel.menuBarTitle.isEmpty ? Text("") : Text(" "))
                + Text(viewModel.menuBarTitle).monospacedDigit()
            )
            .frame(width: 116, alignment: .leading)
        }
        .menuBarExtraStyle(.window)
    }
}

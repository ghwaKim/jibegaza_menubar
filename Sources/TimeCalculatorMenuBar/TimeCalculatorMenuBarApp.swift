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
    private let viewModel = TimeCalculatorViewModel()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let menuBar = MenuBarController(viewModel: viewModel)
        self.menuBar = menuBar
        FlexConnection.shared.start(viewModel: viewModel) { [weak self] in
            guard let self else { return }
            self.viewModel.selectedTab = .week
            self.menuBar?.show()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func didWake() {
        FlexConnection.shared.syncAfterWake()
    }
}

@MainActor
private final class MenuBarController: NSObject, NSPopoverDelegate {
    private let viewModel: TimeCalculatorViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: 116)
    private let popover = NSPopover()
    private var titleUpdates: AnyCancellable?
    private var contentHeight: CGFloat = 560
    private let contentWidth: CGFloat = 470

    init(viewModel: TimeCalculatorViewModel) {
        self.viewModel = viewModel
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.toolTip = "Jibegaza"
        updateTitle()
        titleUpdates = viewModel.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.updateTitle()
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: contentWidth, height: contentHeight)
        let hostingController = NSHostingController(rootView: MenuBarContent(
            viewModel: viewModel, width: contentWidth,
            onHeightChange: { [weak self] height in self?.resize(to: height) }
        ))
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let button = statusItem.button, button.window != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            resize(to: contentHeight)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(popover.isShown)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    private func updateTitle() {
        let time = viewModel.menuBarTitle
        let title = time.isEmpty ? viewModel.menuBarEmoji : "\(viewModel.menuBarEmoji) \(time)"
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ])
    }

    private func resize(to height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        contentHeight = height
        let visibleHeight = statusItem.button?.window?.screen?.visibleFrame.height ?? 760
        let size = NSSize(width: contentWidth, height: min(ceil(height), max(1, visibleHeight - 28)))
        if popover.contentSize != size { popover.contentSize = size }
    }
}

private struct MenuBarContent: View {
    let viewModel: TimeCalculatorViewModel
    let width: CGFloat
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            ContentView()
                .environmentObject(viewModel)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: MenuBarHeightKey.self, value: geometry.size.height)
                    }
                }
        }
        .onPreferenceChange(MenuBarHeightKey.self, perform: onHeightChange)
    }
}

private struct MenuBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

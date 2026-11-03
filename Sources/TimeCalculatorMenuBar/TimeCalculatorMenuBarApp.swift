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
                .frame(width: 470)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        MenuBarWindowSizer(contentSize: geometry.size)
                    }
                }
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

private struct MenuBarWindowSizer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> SizingView {
        SizingView()
    }

    func updateNSView(_ nsView: SizingView, context: Context) {
        nsView.contentSize = contentSize
        nsView.scheduleResize()
    }

    final class SizingView: NSView {
        var contentSize: CGSize = .zero
        private var resizeScheduled = false
        private weak var anchoredWindow: NSWindow?
        private var topEdge: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            anchoredWindow = nil
            topEdge = nil
            scheduleResize()
        }

        func scheduleResize() {
            guard let window else { return }
            if anchoredWindow !== window || !window.isVisible {
                anchoredWindow = window
                topEdge = nil
            }
            if window.isVisible && topEdge == nil {
                topEdge = window.frame.maxY
            }
            guard !resizeScheduled else { return }
            resizeScheduled = true
            // Let SwiftUI finish its layout before updating AppKit's frame.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                self.resizeWindow()
            }
        }

        private func resizeWindow() {
            guard let window, contentSize.width > 0, contentSize.height > 0,
                  contentSize.width.isFinite, contentSize.height.isFinite else { return }
            let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
            var frame = window.frame
            let top = topEdge ?? frame.maxY
            frame.size = size
            frame.origin.y = top - size.height
            if frame != window.frame {
                window.setFrame(frame, display: true, animate: false)
            }
            window.invalidateShadow()
        }
    }
}

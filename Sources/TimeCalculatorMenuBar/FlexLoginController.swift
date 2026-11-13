import AppKit
import SwiftUI
import WebKit

/// Owns the browser and login window. It emits events; sync scheduling lives in FlexConnection.
@MainActor
final class FlexLoginController: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver,
    NSWindowDelegate
{
    let webView: WKWebView
    private var window: NSWindow?
    private var lastObservedAID: String?
    private var cookieReadTask: Task<Void, Never>?
    private var isClearingSession = false

    var onSessionChanged: ((Bool) -> Void)?
    var onNavigationFinished: (() -> Void)?
    var onLoadFailure: (() -> Void)?
    var onClose: (() -> Void)?

    var isVisible: Bool { window?.isVisible == true }

    override init() {
        let configuration = WKWebViewConfiguration()
        // WebKit manages cookies; passwords and session tokens never enter UserDefaults.
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configuration.websiteDataStore.httpCookieStore.add(self)
    }

    func showExisting() { window?.makeKeyAndOrderFront(nil) }

    func open(connection: FlexConnection) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 850, height: 690),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "flex 연결 · 베타버전"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: FlexConnectionView(connection: connection, webView: webView))
            window.center()
            self.window = window
        }
        loadHome()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func loadHome() {
        webView.load(URLRequest(url: URL(string: "https://flex.team/home")!))
    }

    func cookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    }

    func hide() { window?.orderOut(nil) }

    func clearSession(completion: @escaping @MainActor () -> Void) {
        cookieReadTask?.cancel()
        lastObservedAID = nil
        isClearingSession = true
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { entries in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: entries) {
                Task { @MainActor in
                    self.isClearingSession = false
                    completion()
                }
            }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !isClearingSession else { return }
        cookieReadTask?.cancel()
        cookieReadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let cookies = await cookieStore.allCookies()
            let aid = cookies.first { $0.name == "AID" && ["flex.team", ".flex.team"].contains($0.domain) }?.value
            guard !Task.isCancelled, aid != self.lastObservedAID else { return }
            self.lastObservedAID = aid
            self.onSessionChanged?(aid != nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        webView.stopLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.host == "flex.team" { onNavigationFinished?() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadFailure?()
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

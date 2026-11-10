import AppKit
import SwiftUI
import WebKit

@MainActor
final class FlexConnection: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    static let shared = FlexConnection()
    @Published var records: [FlexWorkRecord] = []
    @Published var message = "flex에 로그인하고 회사 선택을 완료해주세요. 로그인 세션으로 이번 주 기록을 조회합니다."
    @Published var isReading = false
    let webView: WKWebView
    private var window: NSWindow?
    private var generation = 0
    private let client = FlexSessionClient()
    private var lastObservedAID: String?
    private var cookieReadTask: Task<Void, Never>?
    private var retryAfterReading = false
    @Published var diagnostic = "대기 중"
    private let deviceID = UUID().uuidString
    @Published var isDisconnecting = false
    private var onImport: (([FlexWorkRecord]) -> String)?

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

    func open(onImport: @escaping ([FlexWorkRecord]) -> String) {
        self.onImport = onImport
        records = []
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "flex 연결 · 베타버전"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FlexConnectionView(connection: self))
            window.center()
            self.window = window
            webView.load(URLRequest(url: URL(string: "https://flex.team/auth/login")!))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !webView.isLoading { readRecords() }
    }

    func readRecords() {
        guard !isDisconnecting else { return }
        guard !isReading else { retryAfterReading = true; return }
        guard let url = webView.url, url.scheme == "https",
              let host = url.host, host == "flex.team" else {
            records = []
            message = "flex에 로그인한 뒤 본인의 근무 화면으로 이동해주세요."
            return
        }
        let generation = self.generation
        isReading = true
        records = []
        message = "로그인 세션으로 이번 주 기록을 조회하고 있습니다."
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isReading = false
                if self.retryAfterReading {
                    self.retryAfterReading = false
                    self.readRecords()
                }
            }
            var stage = "세션 확인"
            self.diagnostic = stage
            let cookies = await self.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard generation == self.generation else { return }
            do {
                stage = "본인 조회"
                self.diagnostic = stage
                let identityData = try await self.client.get(path: FlexAPI.identityPath, cookies: cookies, deviceID: self.deviceID)
                self.diagnostic = "본인 응답 해석"
                stage = self.diagnostic
                let identity = try JSONDecoder().decode(FlexAPI.Identity.self, from: identityData)
                let userID = identity.currentUser.user.userIdHash
                guard !userID.isEmpty, userID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                    throw FlexAPI.Failure.identityMismatch
                }
                guard generation == self.generation else { return }
                let now = Date()
                stage = "근무 조회"
                self.diagnostic = stage
                let data = try await self.client.get(path: FlexAPI.schedulePath(userID: userID, now: now), cookies: cookies, deviceID: self.deviceID)
                stage = "근무 응답 해석"
                self.diagnostic = stage
                let report = try FlexAPI.report(from: data, userID: userID, now: now)
                let records = report.records
                guard generation == self.generation else { return }
                self.records = records
                self.diagnostic = report.diagnostic
                self.message = records.isEmpty
                    ? "조회는 성공했지만 가져오기 조건에 맞는 기록이 없습니다. 아래 날짜별 제외 사유를 확인해주세요."
                    : "API에서 \(records.count)일을 조회했습니다. 조회값은 근무 스케줄 기준이므로 실제 완료한 근무인지 확인 후 반영해주세요. 휴가는 제외합니다."
            } catch {
                guard generation == self.generation else { return }
                self.records = []
                let reason: String
                switch error {
                case FlexSessionClient.Failure.missingSession:
                    reason = "로그인 쿠키(AID)가 없습니다. 회사 선택까지 완료해주세요."
                case FlexSessionClient.Failure.status(let status):
                    reason = status == 401 ? "HTTP 401 · 세션 만료. 다시 로그인해주세요." : "HTTP \(status) · 요청이 거절되었습니다."
                case FlexSessionClient.Failure.contentType:
                    reason = "JSON 대신 다른 형식이 반환되었습니다."
                case let decoding as DecodingError:
                    let context: DecodingError.Context?
                    switch decoding {
                    case .keyNotFound(let key, let c):
                        self.diagnostic = "\(stage) · 누락 필드: \((c.codingPath + [key]).map(\.stringValue).joined(separator: "."))"
                        context = nil
                    case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c): context = c
                    @unknown default: context = nil
                    }
                    if let context {
                        self.diagnostic = "\(stage) · 필드 형식: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                    }
                    reason = "API 응답 필드가 예상과 다릅니다. 아래 진단 문구를 확인해주세요."
                case let network as URLError:
                    reason = "네트워크 오류(\(network.code.rawValue)). 연결 상태를 확인해주세요."
                default:
                    reason = "응답 검증 실패. 다른 계정 또는 중복 날짜 여부를 확인해주세요."
                }
                if !(error is DecodingError) { self.diagnostic = "\(stage) · \(reason)" }
                self.message = reason
            }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !isDisconnecting else { return }
        cookieReadTask?.cancel()
        cookieReadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let cookies = await cookieStore.allCookies()
            let aid = cookies.first { $0.name == "AID" && ["flex.team", ".flex.team"].contains($0.domain) }?.value
            guard !Task.isCancelled, aid != self.lastObservedAID else { return }
            self.lastObservedAID = aid
            self.generation += 1
            self.records = []
            if aid != nil, self.window?.isVisible == true { self.readRecords() }
        }
    }

    func apply() {
        message = onImport?(records) ?? "주간 계산을 다시 열어주세요."
        records = []
    }

    func disconnect() {
        generation += 1
        cookieReadTask?.cancel()
        lastObservedAID = nil
        isDisconnecting = true
        records = []
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { entries in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: entries) {
                self.isDisconnecting = false
                self.message = "연결 정보를 삭제했습니다. 다시 연결하려면 로그인을 눌러주세요."
            }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        generation += 1
        records = []
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readRecords()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        message = "페이지를 열지 못했습니다. 네트워크 상태를 확인해주세요."
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

struct FlexBrowser: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct FlexConnectionView: View {
    @ObservedObject var connection: FlexConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("로그인") {
                    connection.webView.load(URLRequest(url: URL(string: "https://flex.team/auth/login")!))
                }
                .disabled(connection.isDisconnecting)
                Button("이번 주 동기화") { connection.readRecords() }
                    .disabled(connection.isReading || connection.isDisconnecting)
                Spacer()
                Button("연결 정보 삭제") { connection.disconnect() }
                    .disabled(connection.isDisconnecting)
            }
            Text(connection.message).font(.callout).textSelection(.enabled)
            ScrollView {
                Text(connection.diagnostic).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.frame(maxHeight: 110)
            if !connection.records.isEmpty {
                HStack {
                    ForEach(connection.records) { record in
                        VStack {
                            Text(record.date, format: .dateTime.month().day())
                            Text(formatMinutesToKorean(record.minutes))
                        }
                    }
                    Spacer()
                    Button("확인한 기록 반영") { connection.apply() }
                }
            }
            FlexBrowser(webView: connection.webView)
        }.padding(12).frame(minWidth: 800, minHeight: 600)
    }
}

// Monday-based date matching, independent of the system's first weekday preference.
enum FlexImportScope {
    static func index(for date: Date, now: Date, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: today),
              date < today,
              let days = calendar.dateComponents([.day], from: monday, to: calendar.startOfDay(for: date)).day,
              (0..<5).contains(days) else { return nil }
        return days
    }
}

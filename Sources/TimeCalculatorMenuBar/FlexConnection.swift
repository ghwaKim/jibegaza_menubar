import Combine
import Foundation

@MainActor
final class FlexConnection: NSObject, ObservableObject {
    static let shared = FlexConnection()
    @Published var message = "flex에 로그인해주세요. 로그인 세션으로 이번 주 기록을 조회합니다."
    @Published private(set) var todaySyncMessage = "오늘 출근 시각을 아직 동기화하지 않았어요."
    @Published private(set) var todaySyncedAt: Date?
    @Published var isReading = false
    private let login = FlexLoginController()
    @Published private(set) var loginResultTitle: String?
    private var onLoginFinished: ((WorkTab) -> Void)?
    private var loginReturnTab: WorkTab = .week
    private var onClockIn: ((Date, Date) -> Void)?
    private var onImportRecords: (([FlexWorkRecord], Date, Bool) -> String)?
    private var onDisconnect: (() -> Void)?
    private var generation = 0
    private let client = FlexSessionClient()
    private var retryAfterReading = false
    @Published var diagnostic = "대기 중"
    private let deviceID = UUID().uuidString
    @Published var isDisconnecting = false
    @Published private(set) var connected = UserDefaults.standard.bool(forKey: "flex.connected")
    @Published private(set) var needsLogin = false
    @Published private(set) var lastSync: Date?
    @Published var autoSync = UserDefaults.standard.bool(forKey: "flex.autoSync") {
        didSet {
            UserDefaults.standard.set(autoSync, forKey: "flex.autoSync")
            if autoSync, connected {
                readRecords()
            } else if !autoSync, connected, !login.isVisible {
                generation += 1
                retryAfterReading = false
                attemptedRefresh = false
                refreshTask?.cancel()
                message = "자동 동기화를 중지했어요."
            }
        }
    }
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var attemptedRefresh = false
    private let observedShiftKey = "flex.observedShift"

    func start(onClockIn: @escaping (Date, Date) -> Void,
               onImportRecords: @escaping ([FlexWorkRecord], Date, Bool) -> String,
               onDisconnect: @escaping () -> Void,
               onLoginFinished: @escaping (WorkTab) -> Void) {
        self.onClockIn = onClockIn
        self.onImportRecords = onImportRecords
        self.onDisconnect = onDisconnect
        self.onLoginFinished = onLoginFinished
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, self.connected, self.autoSync, !self.needsLogin {
                    self.readRecords()
                }
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    func syncAfterWake() {
        if connected, autoSync, !needsLogin { readRecords() }
    }

    private func setConnected(_ value: Bool) {
        connected = value
        UserDefaults.standard.set(value, forKey: "flex.connected")
    }

    override init() {
        super.init()
        login.onSessionChanged = { [weak self] hasSession in
            guard let self, !self.isDisconnecting else { return }
            self.generation += 1
            if hasSession, self.login.isVisible || (self.connected && self.attemptedRefresh) {
                self.readRecords()
            }
        }
        login.onNavigationFinished = { [weak self] in
            guard let self else { return }
            if self.login.isVisible || self.attemptedRefresh { self.readRecords() }
        }
        login.onClose = { [weak self] in
            self?.generation += 1
            self?.retryAfterReading = false
        }
        login.onLoadFailure = { [weak self] in
            self?.message = "페이지를 열지 못했습니다. 네트워크 상태를 확인해주세요."
        }
    }

    func open(returningTo tab: WorkTab) {
        loginReturnTab = tab
        if login.isVisible {
            login.showExisting()
            return
        }
        generation += 1
        refreshTask?.cancel()
        attemptedRefresh = false
        loginResultTitle = nil
        message = "flex에 로그인하고 회사 선택을 완료해주세요."
        login.open(connection: self)
        if !login.webView.isLoading { readRecords() }
    }

    func readRecords() {
        guard !isDisconnecting else { return }
        guard !isReading else { retryAfterReading = true; return }
        let generation = self.generation
        isReading = true
        loginResultTitle = nil
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
            var verifiedLogin = false
            self.diagnostic = stage
            let cookies = await self.login.cookies()
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
                verifiedLogin = true
                let now = Date()
                var completedToday: FlexWorkRecord?
                var clockStatusFailed = false
                do {
                    completedToday = try await self.readCompletedShift(userID: userID, cookies: cookies, now: now, generation: generation)
                } catch {
                    guard generation == self.generation else { return }
                    clockStatusFailed = true
                    self.todaySyncMessage = "오늘 출근 시각을 가져오지 못했어요. 다시 동기화해주세요."
                }
                guard generation == self.generation else { return }
                stage = "근무 조회"
                self.diagnostic = stage
                let data = try await self.client.get(path: FlexAPI.schedulePath(userID: userID, now: now), cookies: cookies, deviceID: self.deviceID)
                stage = "근무 응답 해석"
                self.diagnostic = stage
                let report = try FlexAPI.report(from: data, userID: userID, now: now)
                let records = report.records + (completedToday.map { [$0] } ?? [])
                guard generation == self.generation else { return }
                self.completeConnection()
                self.lastSync = Date()
                self.message = records.isEmpty ? "이번 주에 가져올 근무기록이 없어요." :
                    (self.onImportRecords?(records, now, true)
                        ?? "주간 기록에 반영할 수 없어요.")
                self.diagnostic = clockStatusFailed ? "오늘 근무 상태 확인 실패\n" + report.diagnostic : report.diagnostic
                self.finishLogin(title: "flex 연결 완료")
            } catch {
                guard generation == self.generation else { return }
                let expired: Bool
                switch error {
                case FlexSessionClient.Failure.missingSession, FlexSessionClient.Failure.status(401): expired = true
                default: expired = false
                }
                if expired, self.connected, !self.login.isVisible, !self.attemptedRefresh {
                    self.refreshSession()
                    return
                }
                if expired, self.connected, !self.login.isVisible {
                    self.needsLogin = true
                }
                let reason: String
                switch error {
                case FlexSessionClient.Failure.missingSession:
                    reason = "로그인 쿠키(AID)가 없습니다. 로그인해주세요."
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
                if stage == "본인 조회" || stage == "본인 응답 해석" {
                    self.todaySyncMessage = reason
                }
                if verifiedLogin, !expired, self.login.isVisible {
                    self.completeConnection()
                    self.message = "flex에 연결했지만 이번 주 근무기록을 가져오지 못했어요."
                    self.finishLogin(title: "근무기록 조회 실패")
                }
            }
        }
    }

    private func readCompletedShift(userID: String, cookies: [HTTPCookie], now: Date,
                                    generation: Int) async throws -> FlexWorkRecord? {
        let path = "/api/v2/time-tracking/work-clock/users/\(userID)/current-status"
        let data = try await client.get(path: path, cookies: cookies, deviceID: deviceID)
        guard generation == self.generation else { return nil }
        let status = try JSONDecoder().decode(FlexAPI.ClockStatus.self, from: data)
        if let clockIn = status.clockInDate(now: now) {
            onClockIn?(clockIn, now)
            todaySyncMessage = "flex 출근 시각을 동기화했어요."
        } else {
            todaySyncMessage = status.isWorking
                ? "flex 출근 시각을 확인할 수 없어요."
                : "오늘 동기화할 출근 기록이 없어요."
        }
        todaySyncedAt = now
        let observed = [userID, status.targetDate]
        if status.isWorking {
            UserDefaults.standard.set(observed, forKey: observedShiftKey)
            return nil
        }
        guard UserDefaults.standard.stringArray(forKey: observedShiftKey) == observed else { return nil }
        return status.completedRecord(userID: userID, now: now)
    }

    private func refreshSession() {
        attemptedRefresh = true
        message = "flex 로그인 상태를 갱신하고 있어요."
        login.loadHome()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.attemptedRefresh else { return }
            self.needsLogin = true
            self.message = "flex에 다시 로그인해주세요."
        }
    }

    private func completeConnection() {
        // On reauthentication, respect the preference already selected for this connection.
        if !connected { autoSync = true }
        setConnected(true)
        needsLogin = false
        attemptedRefresh = false
        refreshTask?.cancel()
        retryAfterReading = false
    }

    private func finishLogin(title: String) {
        guard login.isVisible else { return }
        loginResultTitle = title
        login.hide()
        onLoginFinished?(loginReturnTab)
    }

    func disconnect() {
        generation += 1
        refreshTask?.cancel()
        attemptedRefresh = false
        retryAfterReading = false
        needsLogin = false
        setConnected(false)
        onDisconnect?()
        autoSync = false
        lastSync = nil
        todaySyncedAt = nil
        todaySyncMessage = "오늘 출근 시각을 아직 동기화하지 않았어요."
        loginResultTitle = nil
        UserDefaults.standard.removeObject(forKey: observedShiftKey)
        isDisconnecting = true
        login.clearSession { [weak self] in
            self?.isDisconnecting = false
            self?.message = "flex에서 로그아웃했어요. 다시 연결하려면 로그인해주세요."
        }
    }

}

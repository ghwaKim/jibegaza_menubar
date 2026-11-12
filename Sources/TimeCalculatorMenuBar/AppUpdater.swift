import Combine
import Foundation
import Sparkle

/// Sparkle owns downloading, signature validation, installation, and relaunching.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    private enum UpdateState {
        case current, available, readyToInstall

        var buttonTitle: String {
            switch self {
            case .current: "새 버전 확인"
            case .available: "🔵 새 버전 설치"
            case .readyToInstall: "🔵 재시작하여 업데이트"
            }
        }
    }

    @Published private var updateState: UpdateState = .current
    var buttonTitle: String { updateState.buttonTitle }

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        // A later check can rediscover an already downloaded update.
        if updateState != .readyToInstall {
            updateState = .available
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        updateState = .current
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        updateState = .readyToInstall
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Preserve discovery after transient errors, but don't offer a restart
        // for an installation session that has aborted.
        if updateState == .readyToInstall {
            updateState = .available
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

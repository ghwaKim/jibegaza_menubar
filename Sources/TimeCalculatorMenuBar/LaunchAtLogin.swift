import Foundation
import ServiceManagement

/// Register once; subsequent launches must respect changes made in System Settings.
@MainActor
enum LaunchAtLogin {
    private static let resultKey = "launchAtLogin.initialRegistrationResult"

    enum RegistrationResult: String {
        case attempted, registered, approvalRequired, unavailable, failed
    }

    @discardableResult
    static func registerOnFirstLaunch(
        defaults: UserDefaults = .standard,
        isAppBundle: Bool = Bundle.main.bundleURL.pathExtension == "app",
        isPreview: Bool = WeekRolloverPreview.isEnabled,
        status: () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: () throws -> Void = { try SMAppService.mainApp.register() }
    ) -> RegistrationResult? {
        guard isAppBundle, !isPreview else { return nil }
        if let saved = defaults.string(forKey: resultKey) {
            return RegistrationResult(rawValue: saved)
        }

        // Record the attempt before calling macOS, including failures. Never
        // automatically retry and override a later user decision to disable it.
        defaults.set(RegistrationResult.attempted.rawValue, forKey: resultKey)
        let result: RegistrationResult
        switch status() {
        case .enabled:
            result = .registered
        case .requiresApproval:
            result = .approvalRequired
        case .notRegistered:
            do {
                try register()
                switch status() {
                case .enabled: result = .registered
                case .requiresApproval: result = .approvalRequired
                default: result = .unavailable
                }
            } catch {
                NSLog("Login item registration failed: %@", error.localizedDescription)
                result = .failed
            }
        case .notFound:
            result = .unavailable
        @unknown default:
            result = .unavailable
        }
        defaults.set(result.rawValue, forKey: resultKey)
        if result == .approvalRequired {
            NSLog("Login item requires approval in System Settings > General > Login Items.")
        } else if result == .unavailable {
            NSLog("Login item registration is unavailable. Configure it in System Settings > General > Login Items.")
        }
        return result
    }
}

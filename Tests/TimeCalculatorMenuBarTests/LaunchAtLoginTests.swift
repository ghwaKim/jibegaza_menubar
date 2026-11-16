import Foundation
import ServiceManagement
import Testing
@testable import TimeCalculatorMenuBar

@MainActor
struct LaunchAtLoginTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "LaunchAtLoginTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func registersOnceAndRespectsLaterSystemRemoval() {
        withDefaults { defaults in
            var state: SMAppService.Status = .notRegistered
            var registrations = 0
            let initial = LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { state }, register: { registrations += 1; state = .enabled })
            #expect(initial == .registered)
            // Simulate removal in System Settings and another app launch/update.
            state = .notRegistered
            LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { state }, register: { registrations += 1 })
            #expect(registrations == 1)
            #expect(state == .notRegistered)
        }
    }

    @Test func developmentAndPreviewDoNotConsumeFirstRegistration() {
        withDefaults { defaults in
            for (isApp, isPreview) in [(false, false), (true, true)] {
                let result = LaunchAtLogin.registerOnFirstLaunch(
                    defaults: defaults, isAppBundle: isApp, isPreview: isPreview,
                    status: { Issue.record("Should not query system status"); return .notRegistered },
                    register: { Issue.record("Should not register") })
                #expect(result == nil)
            }
            var state: SMAppService.Status = .notRegistered
            let result = LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { state }, register: { state = .enabled })
            #expect(result == .registered)
        }
    }

    @Test func existingRegistrationAndApprovalAreNotOverridden() {
        for state in [SMAppService.Status.enabled, .requiresApproval, .notFound] {
            withDefaults { defaults in
                let result = LaunchAtLogin.registerOnFirstLaunch(
                    defaults: defaults, isAppBundle: true, isPreview: false,
                    status: { state }, register: { Issue.record("Should not re-register") })
                let expected: LaunchAtLogin.RegistrationResult = switch state {
                case .enabled: .registered
                case .requiresApproval: .approvalRequired
                default: .unavailable
                }
                #expect(result == expected)
                LaunchAtLogin.registerOnFirstLaunch(
                    defaults: defaults, isAppBundle: true, isPreview: false,
                    status: { .notRegistered }, register: { Issue.record("Should not retry") })
            }
        }
    }

    @Test func pendingApprovalAfterRegistrationDoesNotRetry() {
        withDefaults { defaults in
            var state: SMAppService.Status = .notRegistered
            let result = LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { state }, register: { state = .requiresApproval })
            #expect(result == .approvalRequired)
            LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { state }, register: { Issue.record("Should not retry") })
        }
    }

    @Test func failedRegistrationDoesNotRetryOnSubsequentLaunch() {
        struct RegistrationError: Error {}
        withDefaults { defaults in
            let result = LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { .notRegistered }, register: { throw RegistrationError() })
            #expect(result == .failed)
            let next = LaunchAtLogin.registerOnFirstLaunch(
                defaults: defaults, isAppBundle: true, isPreview: false,
                status: { .notRegistered }, register: { Issue.record("Should not retry") })
            #expect(next == .failed)
        }
    }
}

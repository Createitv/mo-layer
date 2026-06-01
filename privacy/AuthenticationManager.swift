import Combine
import Foundation
import SwiftUI

@MainActor
final class AuthenticationManager: ObservableObject {
    enum SessionMode: CaseIterable {
        case cover
        case gestureGate
        case realVault
        case decoyVault
    }

    enum ConfigurationSource: Equatable {
        case none
        case userDefaults
        case secureCredentials
    }

    enum ReauthenticationGracePeriod: Int, CaseIterable, Identifiable {
        case disabled = 0
        case fiveMinutes = 5
        case tenMinutes = 10
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case sixtyMinutes = 60

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .disabled:
                L.string("Always require unlock")
            case .fiveMinutes:
                L.string("5 minutes")
            case .tenMinutes:
                L.string("10 minutes")
            case .fifteenMinutes:
                L.string("15 minutes")
            case .thirtyMinutes:
                L.string("30 minutes")
            case .sixtyMinutes:
                L.string("60 minutes")
            }
        }

        var detail: String {
            switch self {
            case .disabled:
                L.string("Lock every time the app goes to the background.")
            default:
                L.format("Do not ask for Face ID or gesture again within %d minutes after a successful unlock.", rawValue)
            }
        }

        var interval: TimeInterval {
            TimeInterval(rawValue * 60)
        }
    }

    @Published var sessionMode: SessionMode = .cover
    @Published var isConfigured = UserDefaults.standard.bool(forKey: "vault.isConfigured")
    @Published var isGestureUnlockEnabled = GestureCredentialService.hasTemplate
    @Published var isBiometricUnlockEnabled = BiometricAuthService.availability().canEvaluate
    @Published var requiresBiometricUnlock = UserDefaults.standard.object(forKey: biometricRequirementKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(requiresBiometricUnlock, forKey: Self.biometricRequirementKey)
            authMessage = nil
            if !requiresBiometricUnlock && sessionMode == .cover {
                sessionMode = .gestureGate
            }
        }
    }
    @Published var reauthenticationGracePeriod = ReauthenticationGracePeriod(
        rawValue: UserDefaults.standard.integer(forKey: reauthenticationGracePeriodKey)
    ) ?? .disabled {
        didSet {
            UserDefaults.standard.set(reauthenticationGracePeriod.rawValue, forKey: Self.reauthenticationGracePeriodKey)
            if reauthenticationGracePeriod == .disabled {
                lastBackgroundedAt = nil
            }
        }
    }
    @Published var authMessage: String?

    private static let configuredKey = "vault.isConfigured"
    private static let biometricRequirementKey = "vault.requiresBiometricUnlock"
    private static let reauthenticationGracePeriodKey = "vault.reauthenticationGracePeriodMinutes"
    private var lastBackgroundedAt: Date?

    init() {
        refreshConfigurationFromSecureStorage()
    }

    nonisolated static func resolvedConfigurationSource(
        hasConfiguredFlag: Bool,
        hasGestureTemplate: Bool,
        hasRecoverableRootKey: Bool
    ) -> ConfigurationSource {
        guard hasGestureTemplate, hasRecoverableRootKey else {
            return .none
        }
        return hasConfiguredFlag ? .userDefaults : .secureCredentials
    }

    func refreshConfigurationFromSecureStorage() {
        _ = try? VaultCryptoService.restoreRootKeyFromICloudKeychain()
        GestureCredentialService.restoreSyncedCredentialsToLocalKeychainIfAvailable()

        let source = Self.resolvedConfigurationSource(
            hasConfiguredFlag: UserDefaults.standard.bool(forKey: Self.configuredKey),
            hasGestureTemplate: GestureCredentialService.hasTemplate,
            hasRecoverableRootKey: VaultCryptoService.hasRecoverableRootKey()
        )
        isConfigured = source != .none
        isGestureUnlockEnabled = GestureCredentialService.hasTemplate
        isBiometricUnlockEnabled = BiometricAuthService.availability().canEvaluate
        if source == .secureCredentials {
            UserDefaults.standard.set(true, forKey: Self.configuredKey)
        }
    }

    @discardableResult
    func configure(
        backupKey: String,
        gesture: (primary: [GesturePoint], confirmation: [GesturePoint])
    ) async -> Bool {
        do {
            _ = try VaultCryptoService.ensureRootKey()
            let result = try GestureCredentialService.enroll(
                primary: gesture.primary,
                confirmation: gesture.confirmation,
                backupKey: backupKey
            )
            guard result.isMatch else {
                authMessage = L.string("The two gestures are not similar enough. Please set them again.")
                return false
            }
            UserDefaults.standard.set(true, forKey: Self.configuredKey)
            isConfigured = true
            sessionMode = .realVault
            isGestureUnlockEnabled = true
            isBiometricUnlockEnabled = BiometricAuthService.availability().canEvaluate
            authMessage = nil
            return true
        } catch {
            authMessage = L.format("Vault setup failed: %@", error.localizedDescription)
            return false
        }
    }

    func unlockWithGesture(_ points: [GesturePoint]) {
        openFromDisguiseGesture(points)
    }

    func unlockWithBiometrics() async {
        let result = await BiometricAuthService.authenticate(reason: L.string("Authenticate with Face ID before entering your private vault."))
        switch result {
        case .success:
            isBiometricUnlockEnabled = true
            sessionMode = .gestureGate
            authMessage = L.string("Face ID verified. Draw your gesture to continue.")
        case .failure(let error):
            isBiometricUnlockEnabled = BiometricAuthService.availability().canEvaluate
            authMessage = L.format("Face ID verification failed: %@", error.localizedDescription)
        }
    }

    func openFromDisguiseGesture(_ points: [GesturePoint]) {
        guard sessionMode == .gestureGate || !requiresBiometricUnlock else {
            authMessage = L.string("Verify Face ID first.")
            sessionMode = .cover
            return
        }
        do {
            let result = try GestureCredentialService.verify(points)
            guard result.isMatch else {
                openDecoyVault()
                return
            }
            sessionMode = .realVault
            lastBackgroundedAt = nil
            authMessage = nil
        } catch {
            openDecoyVault()
        }
    }

    func openDecoyVault() {
        sessionMode = .decoyVault
        lastBackgroundedAt = nil
        authMessage = nil
    }

    @discardableResult
    func resetGesture(backupKey: String, primary: [GesturePoint], confirmation: [GesturePoint]) -> Bool {
        do {
            let result = try GestureCredentialService.reset(
                primary: primary,
                confirmation: confirmation,
                backupKey: backupKey
            )
            guard result.isMatch else {
                authMessage = GestureCredentialService.verifyBackupKey(backupKey)
                    ? L.string("The two new gestures are not similar enough. Please redraw them.")
                    : L.string("Security code is incorrect.")
                return false
            }
            isGestureUnlockEnabled = true
            authMessage = L.string("Gesture reset. Use the new gesture to enter the vault.")
            return true
        } catch {
            authMessage = L.format("Gesture reset failed: %@", error.localizedDescription)
            return false
        }
    }

    func lock() {
        sessionMode = .cover
        lastBackgroundedAt = nil
        isBiometricUnlockEnabled = BiometricAuthService.availability().canEvaluate
        VaultFileStore.clearTemporaryFiles()
    }

    func shouldLock(for scenePhase: ScenePhase, now: Date = Date()) -> Bool {
        switch scenePhase {
        case .background:
            VaultFileStore.clearTemporaryFiles()
            guard sessionMode == .realVault || sessionMode == .decoyVault else {
                return true
            }
            guard reauthenticationGracePeriod != .disabled else {
                return true
            }
            lastBackgroundedAt = now
            return false
        case .active:
            guard let lastBackgroundedAt else { return false }
            if now.timeIntervalSince(lastBackgroundedAt) > reauthenticationGracePeriod.interval {
                return true
            }
            return false
        case .inactive:
            return false
        @unknown default:
            return false
        }
    }
}

import Combine
import Foundation
import SwiftUI

@MainActor
final class AuthenticationManager: ObservableObject {
    enum SessionMode {
        case cover
        case realVault
        case decoyVault
    }

    @Published var sessionMode: SessionMode = .cover
    @Published var isConfigured = UserDefaults.standard.bool(forKey: "vault.isConfigured")
    @Published var isGestureUnlockEnabled = GestureCredentialService.hasTemplate
    @Published var authMessage: String?

    private let configuredKey = "vault.isConfigured"

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
            UserDefaults.standard.set(true, forKey: configuredKey)
            isConfigured = true
            sessionMode = .cover
            isGestureUnlockEnabled = true
            authMessage = L.string("Vault created. Draw your gesture to enter.")
            return true
        } catch {
            authMessage = L.format("Vault setup failed: %@", error.localizedDescription)
            return false
        }
    }

    func unlockWithGesture(_ points: [GesturePoint]) {
        openFromDisguiseGesture(points)
    }

    func openFromDisguiseGesture(_ points: [GesturePoint]) {
        do {
            let result = try GestureCredentialService.verify(points)
            guard result.isMatch else {
                openDecoyVault()
                return
            }
            sessionMode = .realVault
            authMessage = nil
        } catch {
            openDecoyVault()
        }
    }

    func openDecoyVault() {
        sessionMode = .decoyVault
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
        VaultFileStore.clearTemporaryFiles()
    }
}

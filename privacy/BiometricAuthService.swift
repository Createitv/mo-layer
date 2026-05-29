import Foundation
import LocalAuthentication

enum BiometricAuthService {
    static func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return BiometricAvailability(
            canEvaluate: canEvaluate,
            biometryType: context.biometryType,
            errorDescription: error?.localizedDescription
        )
    }

    static func authenticate(reason: String) async -> Result<Void, Error> {
        let context = LAContext()
        context.localizedCancelTitle = L.string("Cancel")
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success(()) : .failure(BiometricAuthError.failed)
        } catch {
            return .failure(error)
        }
    }
}

struct BiometricAvailability {
    let canEvaluate: Bool
    let biometryType: LABiometryType
    let errorDescription: String?

    var title: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return L.string("Device Authentication")
        }
    }
}

enum BiometricAuthError: LocalizedError {
    case failed

    var errorDescription: String? {
        L.string("Device authentication failed.")
    }
}

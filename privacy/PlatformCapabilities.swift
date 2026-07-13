import SwiftUI
import UIKit

enum PlatformCapabilities {
    #if targetEnvironment(macCatalyst)
    static let isMacCatalyst = true
    #else
    static let isMacCatalyst = false
    #endif

    static var supportsCameraCapture: Bool {
        !isMacCatalyst && UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static var supportsDocumentScanner: Bool {
        !isMacCatalyst
    }

    static var supportsLiveActivities: Bool {
        !isMacCatalyst
    }

    static var supportsHomeScreenQuickActions: Bool {
        !isMacCatalyst
    }

    static var usesDesktopLayout: Bool {
        isMacCatalyst
    }

    @MainActor
    static func selectionChanged() {
        #if !targetEnvironment(macCatalyst)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    @MainActor
    static func successNotification() {
        #if !targetEnvironment(macCatalyst)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

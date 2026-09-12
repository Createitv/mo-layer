import SwiftUI
import UIKit
#if canImport(VisionKit)
import VisionKit
#endif

enum MoLayerPlatform: Equatable {
    case iPhone, iPad, macCatalyst
}
enum MediaCaptureRoute: Equatable { case nativeCamera, importMedia }
enum DocumentScanRoute: Equatable { case visionKit, importMedia }
enum BackgroundProgressRoute: Equatable { case liveActivity, inAppAndNotification }
enum ShortcutEntryRoute: Equatable { case homeScreen, commands }
enum OfferCodeRoute: Equatable { case systemSheet, appStoreInstructions }
enum VideoBrightnessRoute: Equatable { case systemDisplay, playerEffect }

struct PlatformFeatureRoutes: Equatable {
    let mediaCapture: MediaCaptureRoute
    let documentScan: DocumentScanRoute
    let backgroundProgress: BackgroundProgressRoute
    let shortcutEntry: ShortcutEntryRoute
    let offerCode: OfferCodeRoute
    let videoBrightness: VideoBrightnessRoute

    static func resolve(platform: MoLayerPlatform, cameraAvailable: Bool, documentScannerAvailable: Bool) -> Self {
        let desktop = platform == .macCatalyst
        return Self(
            mediaCapture: !desktop && cameraAvailable ? .nativeCamera : .importMedia,
            documentScan: !desktop && documentScannerAvailable ? .visionKit : .importMedia,
            backgroundProgress: desktop ? .inAppAndNotification : .liveActivity,
            shortcutEntry: desktop ? .commands : .homeScreen,
            offerCode: desktop ? .appStoreInstructions : .systemSheet,
            videoBrightness: desktop ? .playerEffect : .systemDisplay
        )
    }
}

enum VaultAdaptiveLayoutMode: Equatable { case stack, split, desktop }
enum VaultAdaptiveLayoutPolicy {
    static func mode(platform: MoLayerPlatform, horizontalSizeClass: UserInterfaceSizeClass?) -> VaultAdaptiveLayoutMode {
        if platform == .macCatalyst { return .desktop }
        return horizontalSizeClass == .regular ? .split : .stack
    }
}

enum VideoBrightnessPolicy {
    static func initialValue(route: VideoBrightnessRoute, systemBrightness: Double) -> Double {
        route == .playerEffect ? 0.5 : systemBrightness
    }
    static func playerEffect(value: Double, route: VideoBrightnessRoute) -> Double {
        route == .playerEffect ? min(max(value - 0.5, -0.5), 0.5) : 0
    }
}

enum PlatformCapabilities {
    #if targetEnvironment(macCatalyst)
    static let isMacCatalyst = true
    #else
    static let isMacCatalyst = false
    #endif

    static var currentPlatform: MoLayerPlatform {
        isMacCatalyst ? .macCatalyst : (UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone)
    }

    static var routes: PlatformFeatureRoutes {
        PlatformFeatureRoutes.resolve(
            platform: currentPlatform,
            cameraAvailable: !isMacCatalyst && UIImagePickerController.isSourceTypeAvailable(.camera),
            documentScannerAvailable: scannerAvailable
        )
    }

    private static var scannerAvailable: Bool {
        #if canImport(VisionKit) && !targetEnvironment(macCatalyst)
        VNDocumentCameraViewController.isSupported
        #else
        false
        #endif
    }

    static var supportsCameraCapture: Bool { routes.mediaCapture == .nativeCamera }
    static var supportsDocumentScanner: Bool { routes.documentScan == .visionKit }
    static var supportsLiveActivities: Bool { routes.backgroundProgress == .liveActivity }
    static var supportsHomeScreenQuickActions: Bool { routes.shortcutEntry == .homeScreen }
    static var usesDesktopLayout: Bool { isMacCatalyst }

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

struct MobileImportKeyboardShortcut: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if PlatformCapabilities.isMacCatalyst {
            content
        } else {
            content.keyboardShortcut("i", modifiers: .command)
        }
    }
}

import Testing
import SwiftUI
@testable import privacy

struct PlatformLayoutTests {
    @Test func hardwareAbsenceHasWorkingImportRoutes() {
        for platform in [MoLayerPlatform.iPhone, .iPad, .macCatalyst] {
            let routes = PlatformFeatureRoutes.resolve(platform: platform, cameraAvailable: false, documentScannerAvailable: false)
            #expect(routes.mediaCapture == .importMedia)
            #expect(routes.documentScan == .importMedia)
        }
    }
    @Test func desktopNeverUsesMobileHardwareEvenWhenReportedAvailable() {
        let routes = PlatformFeatureRoutes.resolve(platform: .macCatalyst, cameraAvailable: true, documentScannerAvailable: true)
        #expect(routes.mediaCapture == .importMedia)
        #expect(routes.documentScan == .importMedia)
        #expect(routes.videoBrightness == .playerEffect)
    }
    @Test func adaptiveLayoutUsesStackOnlyForCompactMobileWidth() {
        #expect(VaultAdaptiveLayoutPolicy.mode(platform: .iPhone, horizontalSizeClass: .compact) == .stack)
        #expect(VaultAdaptiveLayoutPolicy.mode(platform: .iPad, horizontalSizeClass: .regular) == .split)
        #expect(VaultAdaptiveLayoutPolicy.mode(platform: .iPad, horizontalSizeClass: .compact) == .stack)
        #expect(VaultAdaptiveLayoutPolicy.mode(platform: .macCatalyst, horizontalSizeClass: nil) == .desktop)
    }
    @Test func desktopBrightnessStartsNeutralAndClampsWithoutAffectingMobile() {
        #expect(VideoBrightnessPolicy.initialValue(route: .playerEffect, systemBrightness: 0.9) == 0.5)
        #expect(VideoBrightnessPolicy.initialValue(route: .systemDisplay, systemBrightness: 0.9) == 0.9)
        #expect(VideoBrightnessPolicy.playerEffect(value: 0.5, route: .playerEffect) == 0)
        #expect(VideoBrightnessPolicy.playerEffect(value: -1, route: .playerEffect) == -0.5)
        #expect(VideoBrightnessPolicy.playerEffect(value: 2, route: .playerEffect) == 0.5)
        #expect(VideoBrightnessPolicy.playerEffect(value: 1, route: .systemDisplay) == 0)
    }
}

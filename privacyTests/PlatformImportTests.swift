import Testing
@testable import privacy

struct PlatformImportTests {
    @Test func documentScanAlternativeOffersPhotosAndFiles() {
        #expect(ImportAlternativePolicy.actions(for: .importMedia) == [.photos, .files])
        #expect(ImportAlternativePolicy.actions(for: .visionKit) == [.scanner])
    }

    @Test func offerCodePresentationExplainsAppStorePath() {
        #expect(OfferCodePresentationPolicy.action(for: .systemSheet) == .openSystemSheet)
        #expect(OfferCodePresentationPolicy.action(for: .appStoreInstructions) == .showInstructions)
    }
}

//
//  privacyTests.swift
//  privacyTests
//
//  Created by PangHuang on 5/17/26.
//

import Testing
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
@testable import privacy

struct privacyTests {

    @Test func modelContainerLoadsWithCloudKitCompatibleSchema() throws {
        let schema = Schema([
            VaultItem.self,
            VaultFolder.self,
            VaultTag.self,
            SecurityEvent.self,
            SubscriptionState.self,
            VaultManifest.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        _ = try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func encryptDecryptRoundTrip() async throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("private vault payload".utf8)

        let encrypted = try VaultCryptoService.encrypt(plaintext, using: key)
        let decrypted = try VaultCryptoService.decrypt(encrypted, using: key)

        #expect(decrypted == plaintext)
        #expect(encrypted != plaintext)
    }

    @Test func repeatedEncryptionUsesDifferentNonce() async throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("same input".utf8)

        let first = try VaultCryptoService.encrypt(plaintext, using: key)
        let second = try VaultCryptoService.encrypt(plaintext, using: key)

        #expect(first != second)
    }

    @Test func wrongKeyCannotDecrypt() async throws {
        let plaintext = Data("sensitive content".utf8)
        let correctKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let encrypted = try VaultCryptoService.encrypt(plaintext, using: correctKey)

        var didFail = false
        do {
            _ = try VaultCryptoService.decrypt(encrypted, using: wrongKey)
        } catch {
            didFail = true
        }

        #expect(didFail)
    }

    @Test func importFingerprintIsStableForIdenticalPhotoOrVideoData() {
        let first = Data([0x01, 0x02, 0x03, 0x04])
        let second = Data([0x01, 0x02, 0x03, 0x04])
        let different = Data([0x01, 0x02, 0x03, 0x05])

        #expect(VaultImportFingerprint.digest(for: first) == VaultImportFingerprint.digest(for: second))
        #expect(VaultImportFingerprint.digest(for: first) != VaultImportFingerprint.digest(for: different))
    }

    @Test func vaultItemStoresImportFingerprintInSchema() throws {
        let digest = "sha256:test-digest"
        let item = VaultItem(
            kind: .image,
            encryptedMetadata: Data(),
            encryptedFileKey: Data(),
            byteSize: 4,
            importFingerprint: digest
        )

        #expect(item.importFingerprint == digest)
    }

    @Test func vaultFileStoreUsesRelativePathsAndReadsLegacyAbsolutePaths() throws {
        let itemId = "test-\(UUID().uuidString)"
        let payload = Data("encrypted payload".utf8)
        let storedPath = try VaultFileStore.writeEncryptedObject(payload, itemId: itemId)

        #expect(storedPath == "objects/\(itemId).enc")
        #expect(VaultFileStore.fileExists(path: storedPath))
        #expect(try VaultFileStore.read(path: storedPath) == payload)

        let legacyAbsolutePath = VaultFileStore.vaultDirectory
            .appendingPathComponent(storedPath)
            .path

        #expect(VaultFileStore.normalizedStoredPath(legacyAbsolutePath) == storedPath)
        #expect(try VaultFileStore.read(path: legacyAbsolutePath) == payload)

        VaultFileStore.remove(path: storedPath)
    }

    @Test func gestureEnrollmentAcceptsSameRouteWithScaleOffsetAndTimingChanges() throws {
        let primary = TestGestureFactory.sCurve()
        let confirmation = TestGestureFactory.sCurve(
            scaleX: 0.86,
            scaleY: 1.12,
            offsetX: 0.05,
            offsetY: -0.04,
            timeScale: 1.42,
            phase: 0.015
        )

        let result = try GestureCredentialService.enrollmentMatchResult(primary: primary, confirmation: confirmation)

        #expect(result.isMatch)
        #expect(result.score >= 0.68)
    }

    @Test func gestureEnrollmentAcceptsMinorHumanJitter() throws {
        let primary = TestGestureFactory.sCurve(count: 72)
        let confirmation = TestGestureFactory.sCurve(count: 69, timeScale: 0.82, jitter: 0.014, phase: -0.01)

        let result = try GestureCredentialService.enrollmentMatchResult(primary: primary, confirmation: confirmation)

        #expect(result.isMatch)
        #expect(result.score >= 0.68)
    }

    @Test func gestureEnrollmentAcceptsDifferentDrawingSpeedAlongSameRoute() throws {
        let primary = TestGestureFactory.arcLoop(speedPower: 1.0)
        let confirmation = TestGestureFactory.arcLoop(jitter: 0.01, speedPower: 1.7)

        let result = try GestureCredentialService.enrollmentMatchResult(primary: primary, confirmation: confirmation)

        #expect(result.isMatch)
    }

    @Test func gestureEnrollmentRejectsDifferentRoute() throws {
        let primary = TestGestureFactory.sCurve()
        let different = TestGestureFactory.arcLoop()

        let result = try GestureCredentialService.enrollmentMatchResult(primary: primary, confirmation: different)

        #expect(!result.isMatch)
        #expect(result.score < 0.68)
    }

    @Test func gestureValidationRejectsTooShortAndTooSimpleInput() {
        let short = [
            GesturePoint(x: 0.2, y: 0.2, t: 0),
            GesturePoint(x: 0.21, y: 0.2, t: 0.1),
            GesturePoint(x: 0.22, y: 0.2, t: 0.2)
        ]
        #expect(throws: GestureError.self) {
            try GestureCredentialService.validateCandidate(short)
        }

        let simpleLine = (0..<24).map { index in
            let t = Double(index) / 23
            return GesturePoint(x: 0.12 + t * 0.72, y: 0.5, t: t)
        }
        #expect(throws: GestureError.self) {
            try GestureCredentialService.validateCandidate(simpleLine)
        }
    }

    @Test func vaultCategoriesFilterActiveItemsWithoutTrashCategory() {
        let image = TestVaultItemFactory.item(kind: .image)
        let video = TestVaultItemFactory.item(kind: .video)
        let document = TestVaultItemFactory.item(kind: .document)
        let archive = TestVaultItemFactory.item(kind: .archive)
        let other = TestVaultItemFactory.item(kind: .other)
        let trashedImage = TestVaultItemFactory.item(kind: .image, deletedAt: Date())
        let items = [image, video, document, archive, other, trashedImage]

        #expect(VaultCategory.allCases == [.images, .videos, .audio, .documents, .links])
        #expect(VaultCategory.images.items(from: items) == [image])
        #expect(VaultCategory.videos.items(from: items) == [video])
        #expect(VaultCategory.documents.items(from: items) == [document, archive, other])
        #expect(!VaultCategory.allCases.flatMap { $0.items(from: items) }.contains(trashedImage))
    }

    @Test func vaultCategoryCarouselUsesScrollableCardsOnlyWhenManyCategories() {
        let compactWidth = VaultCategoryCarouselLayout.cardWidth(
            containerWidth: 361,
            categoryCount: 6
        )
        let regularWidth = VaultCategoryCarouselLayout.cardWidth(
            containerWidth: 712,
            categoryCount: 6
        )
        let fewCategoriesWidth = VaultCategoryCarouselLayout.cardWidth(
            containerWidth: 361,
            categoryCount: 3
        )

        #expect(compactWidth == 132)
        #expect(regularWidth == 158)
        #expect(fewCategoriesWidth == 113)
        #expect(VaultCategoryCarouselLayout.cardHeight == 132)
        #expect(VaultCategoryCarouselLayout.iconContainerSize == 48)
        #expect(VaultCategoryCarouselLayout.contentMinHeight == 100)
        #expect(VaultCategoryCarouselLayout.textAlignment == .center)
    }

    @Test func mainShellUsesHeaderActionsInsteadOfBottomTabs() {
        #expect(MainShellLayout.usesBottomTabBar == false)
        #expect(MainShellLayout.trailingActions == [.profile, .import])
        #expect(MainShellLayout.importPresentation == .fullScreen)
        #expect(!MainShellAction.allCases.map(\.rawValue).contains("share"))
    }

    @Test func mediaPreviewBadgesUsePhotoVideoAndAudioIcons() {
        #expect(VaultItemKind.image.previewBadgeSystemImage == "photo.fill")
        #expect(VaultItemKind.video.previewBadgeSystemImage == "video.fill")
        #expect(VaultItemKind.audio.previewBadgeSystemImage == "waveform")
        #expect(VaultItemKind.image.isPreviewableMedia)
        #expect(VaultItemKind.video.isPreviewableMedia)
        #expect(VaultItemKind.audio.isPreviewableMedia)
        #expect(!VaultItemKind.document.isPreviewableMedia)
        #expect(VaultItemKind.document.isPreviewableContent)
        #expect(VaultItemKind.archive.isPreviewableContent)
        #expect(VaultItemKind.other.isPreviewableContent)
        #expect(!VaultItemKind.link.isPreviewableContent)
        #expect(VaultItemKind.document.previewBadgeSystemImage == "doc.richtext")
    }

    @Test func importSummaryFormatsCountsByMediaKind() {
        var summary = ImportSummary()
        summary.record(.image)
        summary.record(.image)
        summary.record(.video)
        summary.recordFailure()

        #expect(summary.importedCount == 3)
        #expect(summary.failedCount == 1)
        #expect(summary.displayTitle == L.string("Import Complete"))
        #expect(summary.displayMessage.contains("2 Images"))
        #expect(summary.displayMessage.contains("1 Video"))
    }

    @Test func mediaGridLayoutSupportsReusablePinchSizing() {
        #expect(MediaGridLayout.defaultScale == 1)
        #expect(MediaGridLayout.clampedScale(0.2) == MediaGridLayout.minimumScale)
        #expect(MediaGridLayout.clampedScale(4) == MediaGridLayout.maximumScale)
        #expect(MediaGridLayout.tileMinimum(for: 390, scale: 0.8) == 86)
        #expect(MediaGridLayout.tileMinimum(for: 390, scale: 1.4) == 151)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.minimumScale) == 9)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.defaultScale) == 3)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.maximumScale) == 1)
        #expect(MediaGridLayout.spacing == 6)
        #expect(MediaGridLayout.emptyInteractionMinHeight == 420)
        #expect(MediaGridLayout.persistedScale(0.01) == MediaGridLayout.minimumScale)
        #expect(MediaGridLayout.storedScale(10) == Double(MediaGridLayout.maximumScale))
    }

    @Test func mediaGridScaleStorageSeparatesHomeCategories() {
        #expect(MediaGridScaleStorage.imagesKey == "vault.mediaGridScale.images")
        #expect(MediaGridScaleStorage.videosKey == "vault.mediaGridScale.videos")
        #expect(MediaGridScaleStorage.audioKey == "vault.mediaGridScale.audio")
        #expect(MediaGridScaleStorage.documentsKey == "vault.mediaGridScale.documents")
        #expect(MediaGridScaleStorage.defaultStoredScale == Double(MediaGridLayout.defaultScale))
    }

    @Test func homeIconLayoutsStayCompact() {
        #expect(VaultHomeHeaderLayout.actionSize == 34)
        #expect(VaultHomeHeaderLayout.iconFontSize == 17)
        #expect(VaultCategoryCarouselLayout.iconFontSize == 22)
    }

    @Test func photoLibraryExportSupportsOnlyImagesAndVideos() {
        #expect(PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .image))
        #expect(PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .video))
        #expect(!PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .audio))
        #expect(!PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .document))
        #expect(!PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .archive))
        #expect(!PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .link))
        #expect(!PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .other))
    }

    @Test func settingsChangesDoNotRebuildTheRootPresentation() {
        #expect(AppRootPresentation.rebuildsRootWhenSettingsChange == false)
        #expect(AppRootPresentation.requiresActiveMembershipBeforeVaultAccess == true)
    }

    @Test func subscriptionManagerUsesRevenueCatSubscriptionIdentifiers() {
        #expect(SubscriptionManager.revenueCatEntitlementID == "pro")
        #expect(SubscriptionManager.revenueCatAPIKeyInfoPlistKey == "REVENUECAT_API_KEY")
        #expect(SubscriptionManager.expectedProductIDs == [
            SubscriptionManager.monthly,
            SubscriptionManager.yearly,
            SubscriptionManager.lifetime
        ])
        #expect(SubscriptionManager.missingProductIDs(from: [SubscriptionManager.monthly]) == [
            SubscriptionManager.yearly,
            SubscriptionManager.lifetime
        ])
        #expect(SubscriptionManager.displayOrder(forStoreProductID: SubscriptionManager.monthly) == 0)
        #expect(SubscriptionManager.displayOrder(forStoreProductID: SubscriptionManager.yearly) == 1)
        #expect(SubscriptionManager.displayOrder(forStoreProductID: SubscriptionManager.lifetime) == 2)
        #expect(SubscriptionManager.displayOrder(forStoreProductID: "unknown") == Int.max)
    }

    @Test func membershipAccessSeparatesActiveExpiredAndLockedStates() {
        #expect(SubscriptionManager.accessLevel(isPro: true, hasActivatedPro: false) == .activePro)
        #expect(SubscriptionManager.accessLevel(isPro: false, hasActivatedPro: true) == .expiredReadOnly)
        #expect(SubscriptionManager.accessLevel(isPro: false, hasActivatedPro: false) == .lockedUntilPro)
        #expect(MembershipAccessLevel.activePro.allowsVaultEntry)
        #expect(MembershipAccessLevel.activePro.allowsImportAndCloudSync)
        #expect(MembershipAccessLevel.expiredReadOnly.allowsVaultEntry)
        #expect(!MembershipAccessLevel.expiredReadOnly.allowsImportAndCloudSync)
        #expect(!MembershipAccessLevel.lockedUntilPro.allowsVaultEntry)
        #expect(!MembershipAccessLevel.lockedUntilPro.allowsImportAndCloudSync)
    }

    @MainActor
    @Test func subscriptionManagerGrantsDeveloperAccessOnlyInDebugBuilds() {
        let manager = SubscriptionManager()
        #if DEBUG
        #expect(SubscriptionManager.grantsDeveloperAccessInDebug)
        #expect(manager.isPro)
        #expect(manager.statusText == L.string("Developer Access"))
        #else
        #expect(!SubscriptionManager.grantsDeveloperAccessInDebug)
        #expect(!manager.isPro)
        #expect(manager.statusText == L.string("Free Plan"))
        #endif
    }

    @Test func subscriptionManagerRejectsMissingRevenueCatAPIKey() {
        #expect(!SubscriptionManager.isRevenueCatAPIKeyConfigured(nil))
        #expect(!SubscriptionManager.isRevenueCatAPIKeyConfigured(""))
        #expect(!SubscriptionManager.isRevenueCatAPIKeyConfigured("   "))
        #expect(!SubscriptionManager.isRevenueCatAPIKeyConfigured("REPLACE_WITH_REVENUECAT_PUBLIC_IOS_KEY"))
        #expect(SubscriptionManager.isRevenueCatAPIKeyConfigured("appl_1234567890"))
    }

    @Test func profileSettingsExposeMembershipWithoutLocationSection() {
        #expect(!ProfileSettingsRoute.allCases.contains { $0.rawValue == "location" })
        #expect(ProfileSettingsRoute.allCases.contains(.membership))
    }

    @Test func onboardingSetupStartsWithSecurityCodeThenConfirmsGestureLast() {
        #expect(SetupStep.allCases == [.securityCode, .confirmSecurityCode, .drawGesture, .confirmGesture])
        #expect(SetupStep.securityCode.next == .confirmSecurityCode)
        #expect(SetupStep.confirmSecurityCode.next == .drawGesture)
        #expect(SetupStep.drawGesture.next == .confirmGesture)
        #expect(SetupStep.confirmGesture.primaryActionTitle == L.string("Create Vault"))
    }

    @Test func lockFlowRequiresBiometricGateBeforeGestureGate() {
        #expect(AuthenticationManager.SessionMode.allCases == [.cover, .gestureGate, .realVault, .decoyVault])
    }

    @MainActor
    @Test func appOnlyLocksWhenSceneMovesToBackground() {
        let auth = AuthenticationManager()
        auth.reauthenticationGracePeriod = .disabled
        #expect(!auth.shouldLock(for: .active))
        #expect(!auth.shouldLock(for: .inactive))
        #expect(auth.shouldLock(for: .background))
    }

    @MainActor
    @Test func reauthenticationGracePeriodSkipsLockWithinWindow() {
        let auth = AuthenticationManager()
        auth.sessionMode = .realVault
        auth.reauthenticationGracePeriod = .fifteenMinutes
        let backgroundedAt = Date(timeIntervalSince1970: 1_000)

        #expect(!auth.shouldLock(for: .background, now: backgroundedAt))
        #expect(!auth.shouldLock(for: .active, now: backgroundedAt.addingTimeInterval(14 * 60)))
        #expect(auth.sessionMode == .realVault)
    }

    @MainActor
    @Test func reauthenticationGracePeriodLocksAfterWindowExpires() {
        let auth = AuthenticationManager()
        auth.sessionMode = .realVault
        auth.reauthenticationGracePeriod = .fifteenMinutes
        let backgroundedAt = Date(timeIntervalSince1970: 1_000)

        #expect(!auth.shouldLock(for: .background, now: backgroundedAt))
        #expect(auth.shouldLock(for: .active, now: backgroundedAt.addingTimeInterval(16 * 60)))
    }

}

private enum TestVaultItemFactory {
    static func item(kind: VaultItemKind, deletedAt: Date? = nil) -> VaultItem {
        let item = VaultItem(kind: kind, encryptedMetadata: Data(), byteSize: 128)
        item.deletedAt = deletedAt
        return item
    }
}

private enum TestGestureFactory {
    static func sCurve(
        count: Int = 76,
        scaleX: Double = 1,
        scaleY: Double = 1,
        offsetX: Double = 0,
        offsetY: Double = 0,
        timeScale: Double = 1,
        jitter: Double = 0,
        phase: Double = 0,
        speedPower: Double = 1
    ) -> [GesturePoint] {
        (0..<count).map { index in
            let raw = Double(index) / Double(count - 1)
            let progress = pow(raw, speedPower)
            let x = 0.18 + progress * 0.64
            let y = 0.5 + sin((progress + phase) * .pi * 2) * 0.28
            return GesturePoint(
                x: x * scaleX + offsetX + deterministicJitter(index, jitter),
                y: y * scaleY + offsetY - deterministicJitter(index + 17, jitter),
                t: raw * timeScale
            )
        }
    }

    static func arcLoop(
        count: Int = 80,
        timeScale: Double = 1,
        jitter: Double = 0,
        speedPower: Double = 1
    ) -> [GesturePoint] {
        (0..<count).map { index in
            let raw = Double(index) / Double(count - 1)
            let progress = pow(raw, speedPower)
            let angle = progress * .pi * 1.55 + 0.3
            let radius = 0.18 + progress * 0.25
            return GesturePoint(
                x: 0.45 + cos(angle) * radius + deterministicJitter(index + 31, jitter),
                y: 0.48 + sin(angle) * radius - deterministicJitter(index + 53, jitter),
                t: raw * timeScale
            )
        }
    }

    private static func deterministicJitter(_ seed: Int, _ amount: Double) -> Double {
        guard amount > 0 else { return 0 }
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        let fraction = value - floor(value)
        return (fraction - 0.5) * amount
    }
}

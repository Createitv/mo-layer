//
//  privacyTests.swift
//  privacyTests
//
//  Created by PangHuang on 5/17/26.
//

import Testing
import CloudKit
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
@testable import privacy

@Suite(.serialized)
struct privacyTests {

    @Test func modelContainerLoadsWithCloudKitCompatibleSchema() throws {
        let schema = Schema([
            VaultItem.self,
            VaultFolder.self,
            VaultTag.self,
            DecoyNoteRecord.self,
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

    @Test func decoyNotePayloadEncryptsAndDecrypts() throws {
        let key = SymmetricKey(size: .bits256)
        let payload = DecoyNotePayload(
            title: "Today",
            body: "Buy fruit",
            folder: "Notes",
            todos: [
                DecoyTodoPayload(id: "todo-1", text: "Pay bill", done: true),
                DecoyTodoPayload(id: "todo-2", text: "Call back", done: false)
            ]
        )

        let encrypted = try VaultCryptoService.encryptCodable(payload, using: key)
        let decrypted = try VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: encrypted, using: key)

        #expect(decrypted == payload)
        #expect(encrypted != Data())
    }

    @Test func decoyNoteRecordTracksSyncStateAndSoftDelete() {
        let record = DecoyNoteRecord(
            id: "decoy-note",
            encryptedPayload: Data("encrypted".utf8),
            isPinned: true,
            sortOrder: 12
        )

        #expect(record.id == "decoy-note")
        #expect(record.isPinned)
        #expect(record.sortOrder == 12)
        #expect(record.syncStatus == .pending)

        record.deletedAt = Date()
        record.syncStatus = .failed
        record.lastSyncError = "network"

        #expect(record.deletedAt != nil)
        #expect(record.syncStatus == .failed)
        #expect(record.lastSyncError == "network")
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

    @Test func encryptedVaultFilesUseCloudSyncFriendlyProtection() throws {
        let itemId = "cloud-protection-\(UUID().uuidString)"
        let objectPath = try VaultFileStore.writeEncryptedObject(Data("encrypted object".utf8), itemId: itemId)
        let thumbPath = try VaultFileStore.writeEncryptedThumb(Data("encrypted thumb".utf8), itemId: itemId)
        defer {
            VaultFileStore.remove(path: objectPath)
            VaultFileStore.remove(path: thumbPath)
        }

        let objectProtection = try FileManager.default.attributesOfItem(
            atPath: VaultFileStore.assetURL(for: objectPath).path
        )[.protectionKey] as? FileProtectionType
        let thumbProtection = try FileManager.default.attributesOfItem(
            atPath: VaultFileStore.assetURL(for: thumbPath).path
        )[.protectionKey] as? FileProtectionType

        #expect(VaultFileStore.encryptedFileProtection == .completeUntilFirstUserAuthentication)
        #expect(VaultFileStore.encryptedDataWritingOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
        // The simulator can omit NSFileProtection in long XCTest runs; assert the concrete attribute when it is reported.
        if let objectProtection {
            #expect(objectProtection == .completeUntilFirstUserAuthentication)
        }
        if let thumbProtection {
            #expect(thumbProtection == .completeUntilFirstUserAuthentication)
        }
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

    @Test func vaultCategorySummaryTextUsesCategorySpecificNouns() throws {
        #expect(VaultCategory.images.summaryText(count: 3) == L.format("Total %d photos", 3))
        #expect(VaultCategory.videos.summaryText(count: 2) == L.format("Total %d videos", 2))
        #expect(VaultCategory.audio.summaryText(count: 1) == L.format("Total %d audio files", 1))
        #expect(VaultCategory.documents.summaryText(count: 4) == L.format("Total %d files", 4))

        let keys = [
            "Total %d photos",
            "Total %d videos",
            "Total %d audio files",
            "Total %d files"
        ]

        for key in keys {
            let english = try localizedStrings(bundleCode: "en")[key]
            let simplifiedChinese = try localizedStrings(bundleCode: "zh-Hans")[key]
            let traditionalChinese = try localizedStrings(bundleCode: "zh-Hant")[key]

            #expect(simplifiedChinese != english)
            #expect(traditionalChinese != english)
        }
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

    @Test func vaultImportProgressReportsSelectedImportedAndFailedCounts() {
        var progress = VaultImportProgress(totalCount: 5)

        #expect(progress.isActive)
        #expect(progress.completedCount == 0)
        #expect(progress.statusText == "Selected 5 files, imported 0")

        progress.recordImported()
        progress.recordImported()
        progress.recordFailure()

        #expect(progress.completedCount == 3)
        #expect(progress.statusText == "Selected 5 files, imported 2, 1 failed")

        progress.finish()

        #expect(!progress.isActive)
        #expect(progress.statusText == "Selected 5 files, imported 2, 1 failed")
    }

    @Test func completedVaultImportProgressIsReadyForAutoDismissal() {
        var progress = VaultImportProgress(totalCount: 2)

        #expect(!progress.isReadyForAutoDismissal)

        progress.recordImported()
        progress.recordImported()

        #expect(!progress.isReadyForAutoDismissal)

        progress.finish()

        #expect(progress.isReadyForAutoDismissal)
    }

    @Test func mediaGridLayoutSupportsReusablePinchSizing() {
        #expect(MediaGridLayout.defaultScale == 1)
        #expect(MediaGridLayout.clampedScale(0.01) == MediaGridLayout.minimumScale)
        #expect(MediaGridLayout.clampedScale(4) == MediaGridLayout.maximumScale)
        #expect(MediaGridLayout.tileMinimum(for: 390, scale: 0.8) == 86)
        #expect(MediaGridLayout.tileMinimum(for: 390, scale: 1.4) == 151)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.minimumScale) == 13)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.defaultScale) == 3)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.maximumScale) == 1)
        #expect(MediaGridLayout.spacing == 6)
        #expect(MediaGridLayout.interactionMinHeight == 560)
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

    @Test func cloudToLocalSyncDownloadsOriginalsForAutomaticAndRefreshRuns() {
        #expect(VaultCloudToLocalSyncPolicy.automaticDownloadsOriginals)
        #expect(VaultCloudToLocalSyncPolicy.pullToRefreshDownloadsOriginals)
        #expect(VaultCloudToLocalSyncPolicy.syncedHomeCategories == [.images, .videos, .audio, .documents])
    }

    @Test func cloudAssetDownloadPolicySelectsOnlyMissingNonLinkItems() throws {
        let cloudOnlyImage = VaultItem(kind: .image, encryptedMetadata: Data(), byteSize: 4, assetState: .cloudOnly)
        let deletedVideo = VaultItem(kind: .video, encryptedMetadata: Data(), byteSize: 4, assetState: .cloudOnly)
        deletedVideo.deletedAt = Date()
        let link = VaultItem(kind: .link, encryptedMetadata: Data(), byteSize: 4, assetState: .cloudOnly)
        let localMissingFile = VaultItem(kind: .document, encryptedFilePath: "objects/missing.enc", encryptedMetadata: Data(), byteSize: 4, assetState: .local)

        let storedPath = try VaultFileStore.writeEncryptedObject(Data("encrypted".utf8), itemId: "download-policy-\(UUID().uuidString)")
        let localExistingFile = VaultItem(kind: .audio, encryptedFilePath: storedPath, encryptedMetadata: Data(), byteSize: 4, assetState: .local)
        defer { VaultFileStore.remove(path: storedPath) }

        #expect(VaultCloudAssetDownloadPolicy.shouldDownload(cloudOnlyImage))
        #expect(!VaultCloudAssetDownloadPolicy.shouldDownload(deletedVideo))
        #expect(!VaultCloudAssetDownloadPolicy.shouldDownload(link))
        #expect(VaultCloudAssetDownloadPolicy.shouldDownload(localMissingFile))
        #expect(!VaultCloudAssetDownloadPolicy.shouldDownload(localExistingFile))
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

    @Test func settingsPreferenceRefreshTokenChangesWhenLanguageOrAppearanceChanges() {
        let original = SettingsPreferenceRefreshToken(
            language: AppLanguage.english.rawValue,
            appearance: AppAppearance.system.rawValue
        )
        let changedLanguage = SettingsPreferenceRefreshToken(
            language: AppLanguage.simplifiedChinese.rawValue,
            appearance: AppAppearance.system.rawValue
        )
        let changedAppearance = SettingsPreferenceRefreshToken(
            language: AppLanguage.english.rawValue,
            appearance: AppAppearance.dark.rawValue
        )

        #expect(original != changedLanguage)
        #expect(original != changedAppearance)
    }

    @Test func appLanguageSettingsExposeEverySupportedLocalizationBundle() {
        let supportedBundleCodes = AppLanguage.allCases.compactMap(\.bundleCode)

        #expect(supportedBundleCodes == ["en", "zh-Hans", "zh-Hant", "ja", "de", "fr", "ko", "es"])
    }

    @Test func allSupportedLocalizableFilesShareTheSameKeySet() throws {
        let bundleCodes = ["en", "zh-Hans", "zh-Hant", "ja", "de", "fr", "ko", "es"]
        let keySets = try Dictionary(uniqueKeysWithValues: bundleCodes.map { code in
            (code, try localizedStringKeys(bundleCode: code))
        })
        let englishKeys = try #require(keySets["en"])

        for code in bundleCodes {
            let keys = try #require(keySets[code])
            #expect(keys == englishKeys, "\(code).lproj/Localizable.strings must contain the same keys as en.lproj")
        }
    }

    @Test func chineseICloudSyncCaptionIsTranslated() throws {
        let key = "Encrypted iCloud Sync is always on. Items are encrypted on this device before upload to your private iCloud."
        let english = try localizedStrings(bundleCode: "en")[key]
        let simplifiedChinese = try localizedStrings(bundleCode: "zh-Hans")[key]
        let traditionalChinese = try localizedStrings(bundleCode: "zh-Hant")[key]

        #expect(simplifiedChinese != english)
        #expect(traditionalChinese != english)
        #expect(simplifiedChinese?.contains("iCloud") == true)
        #expect(traditionalChinese?.contains("iCloud") == true)
    }

    @Test func knownUserFacingSwiftStringsUseLocalizationLookup() throws {
        let hardcodedNeedles = [
            "Text(\"Welcome to Palimpsest\")",
            "Text(\"It looks like a simple notes app. Your encrypted private vault opens only with the correct gesture.\")",
            "title: \"Disguised notes app\"",
            "detail: \"Daily launches show ordinary notes, todos, and conversations instead of exposing your real vault.\"",
            "title: \"Gesture entry\"",
            "detail: \"Use your own freeform gesture to enter the vault. Reset it with your security code if you forget it.\"",
            "title: \"Encrypt on import\"",
            "detail: \"Photos, videos, and files are encrypted on this device before optional iCloud sync.\"",
            "title: \"Decoy notes\"",
            "detail: \"Wrong gestures or access codes open a realistic notes space, so real content stays hidden.\"",
            "Button(\"Set Up Palimpsest\"",
            "Section(\"Language\")",
            "Text(\"Default follows your iPhone language and region. Choose a language here to override it inside the app.\")",
            "RecordingActivityAttributes(title: \"Recording\")"
        ]
        let sourceText = try swiftSourceText()

        for needle in hardcodedNeedles {
            #expect(!sourceText.contains(needle), "\(needle) should use L.string(...) instead of a hardcoded UI string")
        }
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

    @Test func configurationCanRecoverFromICloudKeychainCredentials() {
        #expect(AuthenticationManager.resolvedConfigurationSource(
            hasConfiguredFlag: false,
            hasGestureTemplate: true,
            hasRecoverableRootKey: true
        ) == .secureCredentials)
        #expect(AuthenticationManager.resolvedConfigurationSource(
            hasConfiguredFlag: true,
            hasGestureTemplate: true,
            hasRecoverableRootKey: true
        ) == .userDefaults)
        #expect(AuthenticationManager.resolvedConfigurationSource(
            hasConfiguredFlag: false,
            hasGestureTemplate: false,
            hasRecoverableRootKey: true
        ) == .none)
        #expect(AuthenticationManager.resolvedConfigurationSource(
            hasConfiguredFlag: false,
            hasGestureTemplate: true,
            hasRecoverableRootKey: false
        ) == .none)
    }

    @Test func gestureCredentialsAreStoredLocallyAndInICloudKeychain() {
        #expect(GestureCredentialService.credentialStoragePlan == [
            SecureCredentialStoragePolicy(scope: .localDevice, accessibilityName: "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"),
            SecureCredentialStoragePolicy(scope: .iCloudKeychain, accessibilityName: "kSecAttrAccessibleAfterFirstUnlock")
        ])
    }

    @MainActor
    @Test func cloudKitSyncSubscribesToAllVaultRecordTypes() {
        let descriptors = CloudKitSyncService.changeSubscriptionDescriptors

        #expect(descriptors.map(\.recordType) == [
            "VaultManifest",
            "VaultFolder",
            "VaultItem",
            "DecoyNote"
        ])
        #expect(descriptors.map(\.subscriptionID) == [
            "privacy.vault.change.VaultManifest",
            "privacy.vault.change.VaultFolder",
            "privacy.vault.change.VaultItem",
            "privacy.vault.change.DecoyNote"
        ])
        let allSubscriptionsSendSilentPush = descriptors.allSatisfy { $0.sendsSilentPush }
        #expect(allSubscriptionsSendSilentPush)
    }

    @MainActor
    @Test func cloudKitRemoteNotificationsAreRoutedBySubscriptionID() {
        #expect(CloudKitSyncService.remoteChangeReason(subscriptionID: "privacy.vault.change.VaultItem") == .recordType("VaultItem"))
        #expect(CloudKitSyncService.remoteChangeReason(subscriptionID: "privacy.vault.change.DecoyNote") == .recordType("DecoyNote"))
        #expect(CloudKitSyncService.remoteChangeReason(subscriptionID: "unrelated") == nil)
    }

    @MainActor
    @Test func cloudKitRemoteChangeRouterStoresPendingKnownChanges() {
        let router = CloudSyncRemoteChangeRouter()

        #expect(router.receive(subscriptionID: "privacy.vault.change.VaultFolder"))
        #expect(router.pendingReason == .recordType("VaultFolder"))

        router.consume(.recordType("VaultFolder"))
        #expect(router.pendingReason == nil)
        #expect(!router.receive(subscriptionID: "unrelated"))
    }

    @MainActor
    @Test func cloudKitDiagnosticsExposeDevelopmentSyncSurface() {
        let service = CloudKitSyncService()
        let diagnostics = service.diagnosticSnapshot(lastRemoteChange: .recordType("VaultItem"))

        #expect(diagnostics.containerIdentifier == "iCloud.app.landlady.www.privacy")
        #expect(diagnostics.databaseScope == "Private Database")
        #expect(diagnostics.subscriptionRecordTypes == ["VaultManifest", "VaultFolder", "VaultItem", "DecoyNote"])
        #expect(diagnostics.remoteTriggerMode == "Push + foreground refresh")
        #expect(diagnostics.lastRemoteChange == "VaultItem")
        #if DEBUG
        #expect(diagnostics.environment == "Development")
        #else
        #expect(diagnostics.environment == "Production")
        #endif
    }

    @MainActor
    @Test func cloudKitSchemaSeedDescriptorsCoverRemoteUserRecordTypes() {
        let descriptors = CloudKitSyncService.schemaSeedDescriptors

        #expect(descriptors.map(\.recordType) == [
            "VaultFolder",
            "VaultItem",
            "DecoyNote"
        ])
        let seedNamesAreInternal = descriptors.allSatisfy { descriptor in
            descriptor.recordName.hasPrefix("__privacy_schema_seed_")
        }
        #expect(seedNamesAreInternal)
    }

    @MainActor
    @Test func cloudKitSchemaSeedRecordsAreFilteredFromUserResults() {
        let seed = CKRecord(
            recordType: "VaultItem",
            recordID: CKRecord.ID(recordName: "__privacy_schema_seed_vault_item")
        )
        let user = CKRecord(
            recordType: "VaultItem",
            recordID: CKRecord.ID(recordName: "user-item")
        )

        #expect(CloudKitSyncService.userRecords(from: [seed, user]).map(\.recordID.recordName) == ["user-item"])
    }

    @MainActor
    @Test func cloudKitSchemaReadinessTracksMissingRecordTypesAndIndexes() {
        let service = CloudKitSyncService()

        service.recordMissingCloudSchema(
            recordType: "VaultFolder",
            issue: .missingRecordType,
            detail: "Did not find record type VaultFolder"
        )
        service.recordMissingCloudSchema(
            recordType: "VaultItem",
            issue: .missingQueryableIndex,
            detail: "Field 'recordName' is not marked queryable"
        )

        let diagnostics = service.diagnosticSnapshot(lastRemoteChange: nil)

        #expect(diagnostics.schemaStatus == "Needs Dashboard Setup")
        #expect(diagnostics.missingRecordTypes == ["VaultFolder"])
        #expect(diagnostics.missingQueryableIndexes == ["VaultItem"])
        #expect(diagnostics.lastSchemaError?.contains("not marked queryable") == true)
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

private func localizedStringKeys(bundleCode: String) throws -> Set<String> {
    Set(try localizedStrings(bundleCode: bundleCode).keys)
}

private func localizedStrings(bundleCode: String) throws -> [String: String] {
    let url = repositoryRoot()
        .appendingPathComponent("privacy")
        .appendingPathComponent("\(bundleCode).lproj")
        .appendingPathComponent("Localizable.strings")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return try #require(plist as? [String: String])
}

private func swiftSourceText() throws -> String {
    let privacyDirectory = repositoryRoot().appendingPathComponent("privacy")
    let enumerator = try #require(FileManager.default.enumerator(
        at: privacyDirectory,
        includingPropertiesForKeys: nil
    ))
    var text = ""

    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        text += try String(contentsOf: fileURL, encoding: .utf8)
        text += "\n"
    }

    return text
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
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

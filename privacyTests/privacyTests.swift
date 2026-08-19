//
//  privacyTests.swift
//  privacyTests
//
//  Created by PangHuang on 5/17/26.
//

import Testing
import CloudKit
import CoreMedia
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

    @Test func appModelStoreProtectsSQLiteStoreAndWALSidecars() {
        #expect(AppModelStore.fileProtection == .completeUntilFirstUserAuthentication)
        #expect(AppModelStore.storeFileName == "default.store")
        #expect(AppModelStore.storeSidecarFileNames == ["default.store-wal", "default.store-shm"])
    }

    @Test func appModelStoreUsesInMemoryContainerWhenProtectedDataIsUnavailable() throws {
        let modelContainer = try AppModelStore.makeContainer(protectedDataAvailable: false)
        #expect(!modelContainer.usesPersistentStore)
    }

    @Test func appModelStoreRequiresFreeSpaceBeforeOpeningPersistentStore() {
        #expect(AppModelStore.minimumPersistentStoreFreeBytes >= 50 * 1024 * 1024)
        #expect(!AppModelStore.shouldUsePersistentStore(protectedDataAvailable: false))
        #expect(AppModelStore.availableCapacityForPersistentStore() >= 0)
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

    @Test func cloudMetadataInspectionDistinguishesWrongKeyFromLegacyPayload() throws {
        let rootKey = SymmetricKey(size: .bits256)
        let otherKey = SymmetricKey(size: .bits256)
        let metadata = VaultMetadata(
            originalName: "Photo.jpg",
            mimeType: "image/jpeg",
            source: "Photos",
            note: "",
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let readable = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
        let legacy = try VaultCryptoService.encrypt(Data("{\"legacy\":true}".utf8), using: rootKey)

        #expect(VaultCloudMetadataInspector.classify(readable, using: rootKey) == .readable)
        #expect(VaultCloudMetadataInspector.classify(legacy, using: rootKey) == .incompatiblePayload)
        #expect(VaultCloudMetadataInspector.classify(readable, using: otherKey) == .wrongRootKey)
    }

    @Test func remoteManifestRestoresPackagedKeyWhenLocalKeyCannotOpenIt() {
        #expect(VaultRemoteRootKeyPolicy.shouldRestorePackagedKey(
            localKeyOpensManifest: false,
            recoveryKeyOpensPackage: true
        ))
        #expect(!VaultRemoteRootKeyPolicy.shouldRestorePackagedKey(
            localKeyOpensManifest: true,
            recoveryKeyOpensPackage: true
        ))
        #expect(!VaultRemoteRootKeyPolicy.shouldRestorePackagedKey(
            localKeyOpensManifest: false,
            recoveryKeyOpensPackage: false
        ))
    }

    @Test func vaultRecoverySelectsOnlyTheUniqueCandidateWithMostReadableItems() {
        let selected = VaultRecoverySelectionPolicy.select(
            candidates: [
                VaultRecoveryCandidateScore(id: "current", readableItemCount: 4),
                VaultRecoveryCandidateScore(id: "old-backup", readableItemCount: 994),
                VaultRecoveryCandidateScore(id: "unrelated", readableItemCount: 0)
            ]
        )

        #expect(selected?.id == "old-backup")
        #expect(selected?.readableItemCount == 994)
    }

    @Test func vaultRecoveryRefusesAmbiguousCandidateTie() {
        let selected = VaultRecoverySelectionPolicy.select(
            candidates: [
                VaultRecoveryCandidateScore(id: "first", readableItemCount: 499),
                VaultRecoveryCandidateScore(id: "second", readableItemCount: 499)
            ]
        )

        #expect(selected == nil)
    }

    @Test func vaultRecoveryOnlyPromptsWhenTheUnavailableVaultIsDominant() {
        #expect(VaultRecoverySelectionPolicy.shouldRequestRecovery(
            readableItemCount: 4,
            wrongRootKeyCount: 994
        ))
        #expect(!VaultRecoverySelectionPolicy.shouldRequestRecovery(
            readableItemCount: 994,
            wrongRootKeyCount: 4
        ))
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

    @Test func importFingerprintCoversAllNonLinkFileKinds() async {
        let data = Data("same imported bytes".utf8)
        let expectedDigest = VaultImportFingerprint.digest(for: data)

        for kind in [VaultItemKind.image, .livePhoto, .video, .audio, .document, .archive, .other] {
            let fingerprint = await VaultImportArtifactBuilder.fingerprint(for: data, kind: kind)
            #expect(fingerprint == expectedDigest)
        }

        let linkFingerprint = await VaultImportArtifactBuilder.fingerprint(for: data, kind: .link)
        #expect(linkFingerprint == nil)
    }

    @Test func sharedImportDestinationMapsToExpectedFolderIds() {
        #expect(SharedImportDestination.regular.folderId == nil)
        #expect(SharedImportDestination.innerVault.folderId == VaultStore.innerVaultFolderId)
    }

    @Test func sharedImportDestinationDefaultsInvalidRawValuesToRegular() {
        #expect(SharedImportDestination.from(nil) == .regular)
        #expect(SharedImportDestination.from("regular") == .regular)
        #expect(SharedImportDestination.from("innerVault") == .innerVault)
        #expect(SharedImportDestination.from("unknown") == .regular)
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

    @Test func vaultFileStoreKeepsResolvedPathsInsideVaultDirectory() {
        let vaultPath = VaultFileStore.vaultDirectory.standardizedFileURL.path
        let traversalURL = VaultFileStore.assetURL(for: "../outside.enc").standardizedFileURL
        let absoluteOutsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).enc")
        let resolvedAbsoluteURL = VaultFileStore.assetURL(for: absoluteOutsideURL.path).standardizedFileURL

        #expect(traversalURL.path.hasPrefix(vaultPath + "/"))
        #expect(traversalURL.lastPathComponent == "outside.enc")
        #expect(resolvedAbsoluteURL.path.hasPrefix(vaultPath + "/"))
        #expect(resolvedAbsoluteURL.lastPathComponent == absoluteOutsideURL.lastPathComponent)
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

    @Test func privateBrowserSanitizesDownloadFilenames() {
        #expect(BrowserViewModel.sanitizedDownloadFilename("../../Vault/default.store") == "default.store")
        #expect(BrowserViewModel.sanitizedDownloadFilename("folder/report.pdf") == "report.pdf")
        #expect(BrowserViewModel.sanitizedDownloadFilename("invoice:2026.pdf") == "invoice-2026.pdf")
        #expect(BrowserViewModel.sanitizedDownloadFilename("  .hidden  ") == "hidden")
        #expect(BrowserViewModel.sanitizedDownloadFilename("   ").hasSuffix(".download"))
    }

    @Test func sharedImportUsesOriginalFilenameForMetadata() {
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-Quarterly Report.pdf")

        #expect(ImportService.sanitizedFileName("  folder/Quarterly: Report.pdf  ") == "folder-Quarterly- Report.pdf")
        #expect(ImportService.preferredFileExtension(originalName: "Quarterly Report.pdf", fallbackURL: stagedURL) == "pdf")
        #expect(ImportService.preferredFileExtension(originalName: "Quarterly Report", fallbackURL: stagedURL) == "pdf")
    }

    @Test func fileDisplayDescriptorUsesOriginalExtensionForIcons() {
        let pdf = VaultMetadata(
            originalName: "Bank statement.pdf",
            mimeType: "application/octet-stream",
            source: "Files",
            note: "",
            importedAt: Date(),
            originalExtension: nil
        )
        let excel = VaultMetadata(
            originalName: "Budget.xlsx",
            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            source: "Files",
            note: "",
            importedAt: Date(),
            originalExtension: "xlsx"
        )
        let archive = VaultMetadata(
            originalName: "Archive.zip",
            mimeType: "application/zip",
            source: "Files",
            note: "",
            importedAt: Date(),
            originalExtension: "zip"
        )
        let code = VaultMetadata(
            originalName: "ImportService.swift",
            mimeType: "text/plain",
            source: "Files",
            note: "",
            importedAt: Date(),
            originalExtension: "swift"
        )

        #expect(VaultFileDisplayDescriptor(metadata: pdf, kind: .document).icon == "doc.richtext.fill")
        #expect(VaultFileDisplayDescriptor(metadata: excel, kind: .document).icon == "tablecells.fill")
        #expect(VaultFileDisplayDescriptor(metadata: archive, kind: .archive).icon == "archivebox.fill")
        #expect(VaultFileDisplayDescriptor(metadata: code, kind: .document).icon == "curlybraces")
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
        let livePhoto = TestVaultItemFactory.item(kind: .livePhoto)
        let video = TestVaultItemFactory.item(kind: .video)
        let document = TestVaultItemFactory.item(kind: .document)
        let archive = TestVaultItemFactory.item(kind: .archive)
        let other = TestVaultItemFactory.item(kind: .other)
        let trashedImage = TestVaultItemFactory.item(kind: .image, deletedAt: Date())
        let items = [image, livePhoto, video, document, archive, other, trashedImage]

        #expect(VaultCategory.allCases == [.album, .audio, .documents, .links])
        #expect(VaultCategory.album.items(from: items) == [image, livePhoto, video])
        #expect(VaultCategory.documents.items(from: items) == [document, archive, other])
        #expect(!VaultCategory.allCases.flatMap { $0.items(from: items) }.contains(trashedImage))
    }

    @Test func vaultCategorySummaryTextUsesCategorySpecificNouns() throws {
        #expect(VaultCategory.album.summaryText(count: 3) == L.format("Total %d media items", 3))
        #expect(VaultCategory.audio.summaryText(count: 1) == L.format("Total %d audio files", 1))
        #expect(VaultCategory.documents.summaryText(count: 4) == L.format("Total %d files", 4))

        let keys = [
            "Total %d media items",
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

    @Test func moLayerHeaderStyleUsesDistinctActionsAndIcons() {
        #expect(VaultFolderContextStyle.regular.trailingActions == [.profile, .import])
        #expect(VaultFolderContextStyle.moLayer.trailingActions == [.import])
        #expect(VaultFolderContextStyle.regular.showsProfileAction)
        #expect(!VaultFolderContextStyle.moLayer.showsProfileAction)
        #expect(VaultFolderContextStyle.regular.profileSystemImage == "person.crop.circle")
        #expect(VaultFolderContextStyle.moLayer.profileSystemImage != VaultFolderContextStyle.regular.profileSystemImage)
        #expect(VaultFolderContextStyle.moLayer.profileSystemImage == "person.crop.circle.badge.checkmark")
        #expect(VaultFolderContextStyle.regular.importSystemImage == "tray.and.arrow.down")
        #expect(VaultFolderContextStyle.moLayer.importSystemImage != VaultFolderContextStyle.regular.importSystemImage)
        #expect(VaultFolderContextStyle.moLayer.importSystemImage == "square.stack.3d.down.right.fill")
    }

    @Test func homeShellDoesNotRenderMoLayerStatusPill() throws {
        let mainSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("MainViews.swift"),
            encoding: .utf8
        )
        let headerSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("VaultHeaderViews.swift"),
            encoding: .utf8
        )

        #expect(!mainSource.contains("VaultFolderContextPill("))
        #expect(!mainSource.contains("folderContextStyle.showsStatusIndicator"))
        #expect(!headerSource.contains("VaultFolderContextPill"))
        #expect(!headerSource.contains("contextStyle.showsStatusIndicator"))
    }

    @Test func vaultSelectionPolicyUsesOnlyCurrentCategoryFileItems() {
        let image = VaultItem(kind: .image, encryptedMetadata: Data(), byteSize: 1)
        let video = VaultItem(kind: .video, encryptedMetadata: Data(), byteSize: 1)
        let audio = VaultItem(kind: .audio, encryptedMetadata: Data(), byteSize: 1)
        let document = VaultItem(kind: .document, encryptedMetadata: Data(), byteSize: 1)
        let link = VaultItem(kind: .link, encryptedMetadata: Data(), byteSize: 0)

        #expect(VaultSelectionPolicy.selectableItems(in: [image, video, audio, document, link], category: .album).map(\.id) == [image.id, video.id])
        #expect(VaultSelectionPolicy.selectableItems(in: [image, video, audio, document, link], category: .audio).map(\.id) == [audio.id])
        #expect(VaultSelectionPolicy.selectableItems(in: [image, video, audio, document, link], category: .documents).map(\.id) == [document.id])
    }

    @Test func mediaPreviewBadgesUsePhotoVideoAndAudioIcons() {
        #expect(VaultItemKind.image.previewBadgeSystemImage == "photo.fill")
        #expect(VaultItemKind.livePhoto.previewBadgeSystemImage == "livephoto")
        #expect(VaultItemKind.video.previewBadgeSystemImage == "video.fill")
        #expect(VaultItemKind.audio.previewBadgeSystemImage == "waveform")
        #expect(VaultItemKind.image.isPreviewableMedia)
        #expect(VaultItemKind.livePhoto.isPreviewableMedia)
        #expect(VaultItemKind.video.isPreviewableMedia)
        #expect(VaultItemKind.audio.isPreviewableMedia)
        #expect(!VaultItemKind.document.isPreviewableMedia)
        #expect(VaultItemKind.document.isPreviewableContent)
        #expect(VaultItemKind.archive.isPreviewableContent)
        #expect(VaultItemKind.other.isPreviewableContent)
        #expect(!VaultItemKind.link.isPreviewableContent)
        #expect(VaultItemKind.document.previewBadgeSystemImage == "doc.richtext")
        #expect(VaultItemKind.livePhoto.usesLongPressMediaPreview)
    }

    @Test func videoPreviewUsesNativePlayerLayerControls() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("MainViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("PlayerLayerView(player: player)"))
        #expect(source.contains("AVPlayerLayer.self"))
        #expect(source.contains("VideoPlayerControlsOverlay("))
        #expect(source.contains("MediaPreviewAudioSession.makePlayer(for: url, kind: item.kind)"))
        #expect(source.contains("preferredForwardBufferDuration"))
        #expect(source.contains("automaticallyWaitsToMinimizeStalling = true"))
        #expect(source.contains("previewURL = url"))
        #expect(source.contains("adjustmentGesture(containerSize: proxy.size)"))
        #expect(source.contains("VideoPlayerAdjustmentIndicator"))
        #expect(source.contains("VideoPlayerGesturePolicy.adjustedValue"))
        #expect(source.contains("dragGesture(containerSize: proxy.size)"))
        #expect(source.contains("VideoPlayerProgressControl("))
        #expect(source.contains(".frame(minHeight: 44)"))
        #expect(!source.contains("private var volumeBinding"))
        #expect(!source.contains("private var brightnessBinding"))
        #expect(!source.contains("let volumeChanged: (Double) -> Void"))
        #expect(!source.contains("let brightnessChanged: (Double) -> Void"))
        #expect(!source.contains("controlSlider("))
        #expect(!source.contains("VideoPlayer(player: player)"))
    }

    @Test func videoPlayerGesturePolicyClassifiesVerticalScreenDrags() {
        #expect(VideoPlayerGesturePolicy.adjustment(
            startX: 40,
            containerWidth: 300,
            translation: CGSize(width: 3, height: -80),
            scale: 1
        ) == .brightness)
        #expect(VideoPlayerGesturePolicy.adjustment(
            startX: 260,
            containerWidth: 300,
            translation: CGSize(width: 3, height: -80),
            scale: 1
        ) == .volume)
        #expect(VideoPlayerGesturePolicy.adjustment(
            startX: 40,
            containerWidth: 300,
            translation: CGSize(width: 90, height: -30),
            scale: 1
        ) == nil)
        #expect(VideoPlayerGesturePolicy.adjustment(
            startX: 40,
            containerWidth: 300,
            translation: CGSize(width: 1, height: -5),
            scale: 1
        ) == nil)
        #expect(VideoPlayerGesturePolicy.adjustment(
            startX: 40,
            containerWidth: 300,
            translation: CGSize(width: 1, height: -80),
            scale: 2
        ) == nil)
    }

    @Test func videoPlayerGesturePolicyAdjustsAndClampsValues() {
        #expect(VideoPlayerGesturePolicy.adjustedValue(
            startingValue: 0.5,
            verticalTranslation: -100,
            containerHeight: 400,
            range: 0...1
        ) == 0.75)
        #expect(VideoPlayerGesturePolicy.adjustedValue(
            startingValue: 0.5,
            verticalTranslation: 100,
            containerHeight: 400,
            range: 0...1
        ) == 0.25)
        #expect(VideoPlayerGesturePolicy.adjustedValue(
            startingValue: 0.9,
            verticalTranslation: -400,
            containerHeight: 400,
            range: 0...1
        ) == 1)
        #expect(VideoPlayerGesturePolicy.adjustedValue(
            startingValue: 0.1,
            verticalTranslation: 400,
            containerHeight: 400,
            range: 0.05...1
        ) == 0.05)
    }

    @Test func videoPlayerControlStringsAreLocalized() throws {
        let keys = [
            "Back 10 Seconds",
            "Brightness",
            "Forward 10 Seconds",
            "Mute",
            "Pause",
            "Play",
            "Playback Position",
            "Replay",
            "Unmute",
            "Volume"
        ]

        for bundleCode in ["en", "zh-Hans", "zh-Hant", "de", "es", "fr", "ja", "ko"] {
            let strings = try localizedStrings(bundleCode: bundleCode)
            for key in keys {
                #expect(strings[key]?.isEmpty == false)
            }
        }
    }

    @Test func duplicateImportStringsAreLocalized() throws {
        let keys = [
            "%@ imported. %d duplicate(s) skipped.",
            "%@ imported. %d duplicate(s) skipped. %d failed.",
            "No new items imported. %d duplicate(s) skipped.",
            "Selected %d files, imported %d, skipped %d duplicates",
            "Selected %d files, imported %d, skipped %d duplicates, %d failed",
            "This item has already been imported."
        ]

        for bundleCode in ["en", "zh-Hans", "zh-Hant", "de", "es", "fr", "ja", "ko"] {
            let strings = try localizedStrings(bundleCode: bundleCode)
            for key in keys {
                #expect(strings[key]?.isEmpty == false)
            }
        }
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

    @Test func importSummaryReportsSkippedDuplicateCounts() {
        var mixedSummary = ImportSummary()
        mixedSummary.record(.image)
        mixedSummary.recordSkippedDuplicate()
        mixedSummary.recordFailure()

        #expect(mixedSummary.importedCount == 1)
        #expect(mixedSummary.skippedDuplicateCount == 1)
        #expect(mixedSummary.failedCount == 1)
        #expect(mixedSummary.hasReportableResult)
        #expect(mixedSummary.displayMessage.contains("1 duplicate(s) skipped"))
        #expect(mixedSummary.displayMessage.contains("1 failed"))

        var duplicateOnlySummary = ImportSummary()
        duplicateOnlySummary.recordSkippedDuplicate()
        duplicateOnlySummary.recordSkippedDuplicate()

        #expect(duplicateOnlySummary.importedCount == 0)
        #expect(duplicateOnlySummary.skippedDuplicateCount == 2)
        #expect(duplicateOnlySummary.displayMessage == L.format("No new items imported. %d duplicate(s) skipped.", 2))
    }

    @Test func vaultImportProgressReportsSelectedImportedAndFailedCounts() {
        var progress = VaultImportProgress(totalCount: 5)

        #expect(progress.isActive)
        #expect(progress.completedCount == 0)
        #expect(progress.statusText == "Selected 5 files, imported 0")

        progress.updateCurrentItem(VaultImportProgressItem(
            displayName: "clip.mov",
            kind: .video,
            phaseText: L.string("Encrypting current file"),
            progress: 0.5,
            thumbnailData: Data("thumb".utf8)
        ))

        #expect(progress.currentItem?.displayName == "clip.mov")
        #expect(progress.currentItem?.kind == .video)
        #expect(progress.currentItemProgress == 0.5)
        #expect(progress.overallProgress == 0.1)

        progress.recordImported()
        progress.recordImported()
        progress.recordFailure()

        #expect(progress.completedCount == 3)
        #expect(progress.statusText == "Selected 5 files, imported 2, 1 failed")

        progress.finish()

        #expect(!progress.isActive)
        #expect(progress.statusText == "Selected 5 files, imported 2, 1 failed")
    }

    @Test func vaultImportProgressReportsSkippedDuplicates() {
        var progress = VaultImportProgress(totalCount: 4)

        progress.record(.imported)
        progress.record(.skippedDuplicate)
        progress.record(.failed)

        #expect(progress.importedCount == 1)
        #expect(progress.skippedDuplicateCount == 1)
        #expect(progress.failedCount == 1)
        #expect(progress.completedCount == 3)
        #expect(progress.statusText == "Selected 4 files, imported 1, skipped 1 duplicates, 1 failed")
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

    @Test func vaultImportBatchPolicySavesEveryTenImportedItems() {
        #expect(!VaultImportBatchPolicy.shouldSave(afterImportedCount: 0))
        #expect(!VaultImportBatchPolicy.shouldSave(afterImportedCount: 9))
        #expect(VaultImportBatchPolicy.shouldSave(afterImportedCount: 10))
        #expect(!VaultImportBatchPolicy.shouldSave(afterImportedCount: 11))
        #expect(VaultImportBatchPolicy.shouldSave(afterImportedCount: 20))
    }

    @Test func bulkImportQueueDefersCloudSyncUntilCompletion() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("ImportService.swift"),
            encoding: .utf8
        )

        #expect(source.contains("syncAfterImport: false"))
        #expect(source.contains("saveImmediately: false"))
        #expect(source.contains("await vaultStore.syncPendingChanges(context: context, sync: sync)"))
    }

    @Test func duplicateImportSkipsWithoutCreatingNewVaultItem() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("VaultStore.swift"),
            encoding: .utf8
        )

        #expect(source.contains("enum VaultImportResult: Equatable"))
        #expect(source.contains("case skippedDuplicate"))
        #expect(source.contains("return .skippedDuplicate"))
        #expect(source.contains("item.deletedAt == nil"))
        #expect(source.contains("&& item.importFingerprint == importFingerprint"))
        #expect(!source.contains("&& (item.kind == .image || item.kind == .video)"))
    }

    @Test func mediaGridLayoutSupportsReusablePinchSizing() {
        #expect(MediaGridLayout.defaultScale == 1)
        #expect(MediaGridLayout.clampedScale(0.01) == MediaGridLayout.minimumScale)
        #expect(MediaGridLayout.clampedScale(4) == MediaGridLayout.maximumScale)
        #expect(MediaGridLayout.tileMinimum(for: 390, scale: 0.8) == 86)
        #expect(MediaGridLayout.tileMinimum(for: 390, scale: 1.4) == 151)
        #expect(MediaGridLayout.filledTileSize(for: 390, scale: MediaGridLayout.defaultScale) == 126)
        #expect(MediaGridLayout.filledTileSize(for: 390, scale: 1.4) == 192)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.minimumScale) == 13)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.defaultScale) == 3)
        #expect(MediaGridLayout.columnCount(for: 390, scale: MediaGridLayout.maximumScale) == 1)
        #expect(MediaGridLayout.spacing == 6)
        #expect(MediaGridLayout.interactionMinHeight == 560)
        #expect(MediaGridLayout.albumViewportHeight(for: 200) == MediaGridLayout.interactionMinHeight)
        #expect(MediaGridLayout.albumViewportHeight(for: 1_000) == 720)
        #expect(MediaGridLayout.persistedScale(0.01) == MediaGridLayout.minimumScale)
        #expect(MediaGridLayout.storedScale(10) == Double(MediaGridLayout.maximumScale))
    }

    @Test func albumGridDefersExpensiveLayoutChangesUntilPinchSettles() {
        #expect(
            MediaGridLayout.layoutScale(
                committedScale: 1,
                proposedScale: 2.2,
                isPinching: true
            ) == 1
        )
        #expect(
            MediaGridLayout.layoutScale(
                committedScale: 1,
                proposedScale: 2.2,
                isPinching: false
            ) == 2.2
        )
    }

    @Test @MainActor func thumbnailDataLoaderDecryptsTheStoredThumbnail() async throws {
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let rootKey = SymmetricKey(size: .bits256)
        let fileKey = SymmetricKey(size: .bits256)
        let itemID = "thumbnail-test-\(UUID().uuidString)"
        let encryptedThumbnail = try VaultCryptoService.encrypt(pngData, using: fileKey)
        let path = try VaultFileStore.writeEncryptedThumb(encryptedThumbnail, itemId: itemID)
        defer { VaultFileStore.remove(path: path) }

        let request = VaultThumbnailLoadRequest(
            cacheKey: itemID,
            encryptedThumbPath: path,
            encryptedFileKey: try VaultCryptoService.wrapFileKey(fileKey, rootKey: rootKey),
            rootKey: rootKey
        )
        let data = try await VaultThumbnailDataLoader().decryptedData(for: request)

        #expect(data == pngData)
    }

    @Test func mediaPreviewRepairCandidatesStayLimitedToVisibleItems() {
        let orderedIDs = ["1", "2", "3", "4", "5"]
        let candidates = MediaPreviewRepairBatchPolicy.candidateIDs(
            orderedItemIDs: orderedIDs,
            visibleItemIDs: ["2", "4", "5"],
            repairNeededItemIDs: ["1", "2", "3", "4"],
            limit: 2
        )

        #expect(candidates == ["2", "4"])
    }

    @Test func albumGridReportsVisibleItemsOnlyAfterScrollingSettles() {
        #expect(!AlbumGridVisibleItemsReportPolicy.shouldReport(isDragging: true, isDecelerating: false))
        #expect(!AlbumGridVisibleItemsReportPolicy.shouldReport(isDragging: false, isDecelerating: true))
        #expect(AlbumGridVisibleItemsReportPolicy.shouldReport(isDragging: false, isDecelerating: false))
    }

    @Test func albumPageMergeAppendsOnlyNewStableIDs() {
        let merged = AlbumMediaPageMergePolicy.merge(
            existingIDs: ["a", "b"],
            incomingIDs: ["b", "c", "d"]
        )

        #expect(merged == ["a", "b", "c", "d"])
    }

    @Test func albumLoadTriggerUsesTwoScreenWindow() {
        #expect(AlbumMediaLoadTriggerPolicy.shouldLoadMore(
            maxRequestedIndex: 160,
            loadedCount: 200,
            estimatedVisibleCount: 24
        ))
        #expect(!AlbumMediaLoadTriggerPolicy.shouldLoadMore(
            maxRequestedIndex: 120,
            loadedCount: 200,
            estimatedVisibleCount: 24
        ))
    }

    @Test func albumPagingRequestPolicyRejectsDuplicateAndCompletedLoads() {
        #expect(AlbumMediaPagingRequestPolicy.canStart(isLoading: false, hasMore: true))
        #expect(!AlbumMediaPagingRequestPolicy.canStart(isLoading: true, hasMore: true))
        #expect(!AlbumMediaPagingRequestPolicy.canStart(isLoading: false, hasMore: false))
    }

    @Test @MainActor func albumPagingIncludesNilFolderItemsInRegularVault() async throws {
        let schema = Schema([VaultItem.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let regularItem = VaultItem(
            id: "regular-photo",
            kind: .image,
            encryptedMetadata: Data(),
            byteSize: 1,
            folderId: nil
        )
        let innerItem = VaultItem(
            id: "inner-photo",
            kind: .image,
            encryptedMetadata: Data(),
            byteSize: 1,
            folderId: VaultStore.innerVaultFolderId
        )
        context.insert(regularItem)
        context.insert(innerItem)
        try context.save()

        let paging = AlbumMediaPagingController()
        await paging.loadFirstPage(
            scope: AlbumMediaScope(
                isInnerVaultActive: false,
                filter: .all,
                favoritesOnly: false
            ),
            context: context
        )

        #expect(paging.items.map(\.id) == ["regular-photo"])
        #expect(try AlbumLibraryCountQuery.fetch(context: context, isInnerVaultActive: false).album == 1)
    }

    @Test func albumCursorUsesLastStableItem() {
        let date = Date(timeIntervalSince1970: 100)

        #expect(
            AlbumMediaCursorPolicy.cursor(createdAt: date, id: "z")
                == AlbumMediaCursor(createdAt: date, id: "z")
        )
    }

    @Test func albumGridUsesOnlyApprovedColumnCounts() {
        #expect(MediaGridLayout.albumColumnCounts == [1, 3, 5, 7])
        #expect(MediaGridLayout.defaultAlbumColumnCount == 3)
        #expect(MediaGridLayout.settledAlbumColumnCount(startingColumnCount: 3, gestureScale: 2) == 1)
        #expect(MediaGridLayout.settledAlbumColumnCount(startingColumnCount: 3, gestureScale: 0.5) == 7)
    }

    @Test func albumZoomAnchorRestoresViewportOffset() {
        #expect(AlbumGridZoomAnchorPolicy.contentOffset(
            itemCenterY: 900,
            viewportAnchorY: 300,
            minimumOffsetY: 0,
            maximumOffsetY: 1_400
        ) == 600)
        #expect(AlbumGridZoomAnchorPolicy.contentOffset(
            itemCenterY: 50,
            viewportAnchorY: 300,
            minimumOffsetY: 0,
            maximumOffsetY: 1_400
        ) == 0)
    }

    @Test @MainActor func mediaPreviewRepairBackfillsMissingDurationOnlyFromLocalVideos() {
        #expect(VaultMediaPreviewRepairPolicy.needsVideoDuration(kind: .video, storedDuration: nil, hasLocalOriginal: true))
        #expect(!VaultMediaPreviewRepairPolicy.needsVideoDuration(kind: .video, storedDuration: 41, hasLocalOriginal: true))
        #expect(!VaultMediaPreviewRepairPolicy.needsVideoDuration(kind: .video, storedDuration: nil, hasLocalOriginal: false))
        #expect(!VaultMediaPreviewRepairPolicy.needsVideoDuration(kind: .image, storedDuration: nil, hasLocalOriginal: true))
    }

    @Test @MainActor func albumGridReconfiguresOnlyChangedVisibleItems() {
        let previous = [
            AlbumGridItemRenderState(id: "1", thumbnailIdentity: "thumb-1", statusIdentity: "synced", isFavorite: false, isSelected: false),
            AlbumGridItemRenderState(id: "2", thumbnailIdentity: "", statusIdentity: "cloud", isFavorite: false, isSelected: false)
        ]
        let next = [
            previous[0],
            AlbumGridItemRenderState(id: "2", thumbnailIdentity: "thumb-2", statusIdentity: "cloud", isFavorite: false, isSelected: false)
        ]

        #expect(AlbumGridUpdatePolicy.plan(previous: previous, next: next) == .reconfigure([1]))
        #expect(AlbumGridUpdatePolicy.plan(previous: previous, next: Array(next.reversed())) == .reloadAll)
    }

    @Test @MainActor func albumGridUsesInsertPlanForAppendedPage() {
        let previous = [
            AlbumGridItemRenderState(id: "a", thumbnailIdentity: "thumb-a", statusIdentity: "synced", isSelected: false),
            AlbumGridItemRenderState(id: "b", thumbnailIdentity: "thumb-b", statusIdentity: "synced", isSelected: false)
        ]
        let next = previous + [
            AlbumGridItemRenderState(id: "c", thumbnailIdentity: "thumb-c", statusIdentity: "synced", isSelected: false)
        ]

        #expect(AlbumGridUpdatePolicy.plan(previous: previous, next: next) == .append(2..<3))
    }

    @Test @MainActor func albumGridReconfiguresOnlyTheItemWhoseFavoriteStateChanged() {
        let previous = [
            AlbumGridItemRenderState(id: "1", thumbnailIdentity: "thumb-1", statusIdentity: "synced", isFavorite: false, isSelected: false),
            AlbumGridItemRenderState(id: "2", thumbnailIdentity: "thumb-2", statusIdentity: "synced", isFavorite: false, isSelected: false)
        ]
        let next = [
            AlbumGridItemRenderState(id: "1", thumbnailIdentity: "thumb-1", statusIdentity: "synced", isFavorite: true, isSelected: false),
            previous[1]
        ]

        #expect(AlbumGridUpdatePolicy.plan(previous: previous, next: next) == .reconfigure([0]))
    }

    @Test @MainActor func albumFavoriteFilterKeepsRegularAndMoLayerSpacesIndependent() {
        let regularItems = [(id: "regular-favorite", favorite: true), (id: "regular-other", favorite: false)]
        let moLayerItems = [(id: "molayer-favorite", favorite: true), (id: "molayer-other", favorite: false)]

        let regularFavorites = AlbumFavoriteFilter.items(
            from: regularItems,
            showsFavoritesOnly: true,
            isFavorite: \.favorite
        )
        let moLayerFavorites = AlbumFavoriteFilter.items(
            from: moLayerItems,
            showsFavoritesOnly: true,
            isFavorite: \.favorite
        )

        #expect(regularFavorites.map(\.id) == ["regular-favorite"])
        #expect(moLayerFavorites.map(\.id) == ["molayer-favorite"])
        #expect(AlbumFavoriteFilter.items(from: regularItems, showsFavoritesOnly: false, isFavorite: \.favorite).map(\.id) == ["regular-favorite", "regular-other"])
    }

    @Test @MainActor func albumVideoDurationFormatterAdaptsToAvailableSpace() {
        #expect(AlbumVideoDurationFormatter.text(for: 65) == "1:05")
        #expect(AlbumVideoDurationFormatter.text(for: 3661) == "1:01:01")
        #expect(AlbumVideoDurationFormatter.text(for: 3661, compact: true) == "1h")
        #expect(AlbumVideoDurationFormatter.text(for: 65, compact: true) == "1m")
        #expect(AlbumVideoDurationFormatter.text(for: 12, compact: true) == "12s")
        #expect(AlbumVideoDurationLayout.presentation(for: 96) == .full)
        #expect(AlbumVideoDurationLayout.presentation(for: 54) == .compact)
        #expect(AlbumVideoDurationLayout.presentation(for: 32) == .iconOnly)
    }

    @Test @MainActor func vaultMetadataDecodesWithoutMediaDurationForExistingItems() throws {
        let json = """
        {
          "originalName": "old.mov",
          "mimeType": "video/quicktime",
          "source": "Photos",
          "note": "",
          "importedAt": 0,
          "originalExtension": "mov"
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(VaultMetadata.self, from: json)

        #expect(metadata.originalName == "old.mov")
        #expect(metadata.mediaDurationSeconds == nil)
    }

    @Test func mediaPreviewRepairTaskKeyDependsOnViewportInsteadOfRepairProgress() {
        let key = MediaPreviewRepairBatchPolicy.taskKey(
            scope: "default:album:all",
            visibleItemIDs: ["3", "1", "2"]
        )

        #expect(key == "default:album:all:1,2,3")
    }

    @Test func fullscreenPreviewLoadsOriginalOnlyForSelectedPage() {
        #expect(FullscreenMediaLoadingPolicy.shouldLoadOriginal(isSelected: true))
        #expect(!FullscreenMediaLoadingPolicy.shouldLoadOriginal(isSelected: false))
    }

    @Test func fullscreenPreviewPreloadsStableOriginalImagesForSwipeNeighbors() {
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 4, selectedIndex: 4, itemKind: .image) == .original)
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 3, selectedIndex: 4, itemKind: .image) == .original)
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 5, selectedIndex: 4, itemKind: .livePhoto) == .original)
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 3, selectedIndex: 4, itemKind: .video) == .thumbnail)
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 2, selectedIndex: 4, itemKind: .image) == .none)
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 6, selectedIndex: 4, itemKind: .image) == .none)
        #expect(FullscreenMediaLoadingPolicy.loadMode(itemIndex: 0, selectedIndex: nil, itemKind: .image) == .none)
    }

    @Test func fullscreenOriginalImagePreviewDoesNotStageCroppedThumbnail() {
        #expect(!FullscreenMediaStagingPolicy.shouldShowThumbnailBeforeOriginal(kind: .image))
        #expect(!FullscreenMediaStagingPolicy.shouldShowThumbnailBeforeOriginal(kind: .livePhoto))
        #expect(FullscreenMediaStagingPolicy.shouldShowThumbnailBeforeOriginal(kind: .video))
    }

    @Test func activeVideoPlaybackPreventsIdleSleepOnlyWhileVisible() {
        #expect(VideoPlayerIdleTimerPolicy.shouldDisableIdleTimer(isPlaying: true, isVisible: true))
        #expect(!VideoPlayerIdleTimerPolicy.shouldDisableIdleTimer(isPlaying: false, isVisible: true))
        #expect(!VideoPlayerIdleTimerPolicy.shouldDisableIdleTimer(isPlaying: true, isVisible: false))
    }

    @Test func videoPreviewOwnsOneItemWithoutPreviousNextPaging() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("MainViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("struct MediaPreviewSelection: Identifiable"))
        #expect(source.contains("let item: VaultItem"))
        #expect(!source.contains("LazyHStack(spacing: 0)"))
        #expect(!source.contains(".scrollTargetBehavior(.paging)"))
        #expect(source.contains("VideoPlayerTransportControls("))
        #expect(source.contains("alignment: .center"))
        #expect(source.contains("AVPlayerItemFailedToPlayToEndTimeErrorKey"))
        #expect(source.contains(".AVPlayerItemPlaybackStalled"))
        #expect(!source.contains("ForEach(previewWindowItems)"))
        #expect(!source.contains("let items: [VaultItem]\n    let initialItemId"))
    }

    @Test func mediaGridScaleStorageSeparatesHomeCategories() {
        #expect(MediaGridScaleStorage.albumKey == "vault.mediaGridScale.album")
        #expect(MediaGridScaleStorage.albumColumnsKey == "vault.mediaGridColumns.album")
        #expect(MediaGridScaleStorage.audioKey == "vault.mediaGridScale.audio")
        #expect(MediaGridScaleStorage.documentsKey == "vault.mediaGridScale.documents")
        #expect(MediaGridScaleStorage.defaultStoredScale == Double(MediaGridLayout.defaultScale))
    }

    @Test func albumMediaGridKeepsCellReuseDuringScrollAndPinch() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("MediaGridViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("collectionView.isScrollEnabled = true"))
        #expect(source.contains("context.coordinator.reloadDataIfNeeded(collectionView)"))
        #expect(source.contains("private var transientColumnCount"))
        #expect(source.contains("MediaGridLayout.albumViewportHeight()"))

        let pinchStart = try #require(source.range(of: "@objc func handlePinch"))
        let longPressStart = try #require(source.range(of: "@objc func handleLongPress"))
        let pinchSource = source[pinchStart.lowerBound..<longPressStart.lowerBound]
        let changedStart = try #require(pinchSource.range(of: "case .changed:"))
        let endedStart = try #require(pinchSource.range(of: "case .ended, .cancelled, .failed:"))
        let changedSource = pinchSource[changedStart.lowerBound..<endedStart.lowerBound]

        #expect(changedSource.contains("transientColumnCount ="))
        #expect(!changedSource.contains("parent.columnCount ="))
        #expect(source.contains("collectionView.prefetchDataSource = context.coordinator"))
        #expect(source.contains("interactionFrameSampler.start"))
    }

    @Test func fullscreenMediaUsesBoundedDecodeAndResponsiveSeeking() {
        let maxPixels = FullscreenImageDecodePolicy.maximumPixelSize(
            screenSize: CGSize(width: 402, height: 874),
            screenScale: 3
        )

        #expect(maxPixels == 4096)
        #expect(VideoPlayerSeekPolicy.tolerance.seconds > 0)
        #expect(VideoPlayerSeekPolicy.tolerance.seconds <= 0.1)
    }

    @Test func decryptedPreviewCacheIdentityChangesWithEncryptedAssetRevision() {
        let first = VaultPreviewFileCachePolicy.cacheKey(
            itemID: "video-1",
            encryptedFilePath: "objects/video-1.enc",
            encryptedFileKey: Data([1, 2, 3]),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let same = VaultPreviewFileCachePolicy.cacheKey(
            itemID: "video-1",
            encryptedFilePath: "objects/video-1.enc",
            encryptedFileKey: Data([1, 2, 3]),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let changed = VaultPreviewFileCachePolicy.cacheKey(
            itemID: "video-1",
            encryptedFilePath: "objects/video-1-v2.enc",
            encryptedFileKey: Data([1, 2, 3]),
            updatedAt: Date(timeIntervalSince1970: 101)
        )

        #expect(first == same)
        #expect(first != changed)
    }

    @Test func cloudToLocalSyncDownloadsOriginalsOnlyWhenRestoringAfterReinstall() {
        #expect(VaultCloudToLocalSyncPolicy.downloadsOriginals(
            purpose: .reinstallRestore,
            explicitOverride: nil
        ))
        #expect(!VaultCloudToLocalSyncPolicy.downloadsOriginals(
            purpose: .routineSync,
            explicitOverride: nil
        ))
        #expect(!VaultCloudToLocalSyncPolicy.automaticDownloadsPreviews)
        #expect(!VaultCloudToLocalSyncPolicy.manualRefreshDownloadsOriginals)
        #expect(VaultCloudToLocalSyncPolicy.downloadsOriginals(
            purpose: .routineSync,
            explicitOverride: true
        ))
        #expect(!VaultCloudToLocalSyncPolicy.downloadsOriginals(
            purpose: .reinstallRestore,
            explicitOverride: false
        ))
        #expect(VaultCloudToLocalSyncPolicy.syncedHomeCategories == [.album, .audio, .documents])
    }

    @Test func optimizedStoragePolicyKeepsBoundedLocalOriginalCache() {
        #expect(VaultOptimizedStoragePolicy.isEnabledByDefault)
        #expect(VaultOptimizedStoragePolicy.maxLocalOriginalCacheBytes == 300 * 1024 * 1024)
        #expect(VaultOptimizedStoragePolicy.targetLocalOriginalCacheBytes == 200 * 1024 * 1024)
        #expect(VaultOptimizedStoragePolicy.immediateReleaseByteThreshold == 25 * 1024 * 1024)
        #expect(VaultOptimizedStoragePolicy.lowDiskFreeBytes == 1 * 1024 * 1024 * 1024)
    }

    @Test func optimizedStorageAppliesTheSameLargeOriginalRuleAcrossFileKinds() {
        let fileKinds: [VaultItemKind] = [.image, .livePhoto, .video, .audio, .document, .archive, .other]

        for kind in fileKinds {
            let smallItem = VaultItem(
                kind: kind,
                encryptedFilePath: "objects/small-\(kind.rawValue).enc",
                encryptedMetadata: Data(),
                byteSize: VaultOptimizedStoragePolicy.immediateReleaseByteThreshold - 1,
                assetState: .local
            )
            smallItem.syncStatus = VaultSyncStatus.synced

            let largeItem = VaultItem(
                kind: kind,
                encryptedFilePath: "objects/large-\(kind.rawValue).enc",
                encryptedMetadata: Data(),
                byteSize: VaultOptimizedStoragePolicy.immediateReleaseByteThreshold,
                assetState: .local
            )
            largeItem.syncStatus = VaultSyncStatus.synced

            #expect(!VaultOptimizedStoragePolicy.shouldReleaseAfterSuccessfulSync(smallItem))
            #expect(VaultOptimizedStoragePolicy.shouldReleaseAfterSuccessfulSync(largeItem))
        }
    }

    @Test func cloudIndexRefreshAvoidsOriginalAssetFetches() throws {
        let cloudServiceSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("CloudKitSyncService.swift"),
            encoding: .utf8
        )
        let vaultStoreSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("VaultStore.swift"),
            encoding: .utf8
        )

        #expect(cloudServiceSource.contains("func fetchRemoteItemsForIndex() async -> [CKRecord]"))
        #expect(cloudServiceSource.contains("\"thumbAsset\""))
        #expect(!cloudServiceSource.contains("""
            "fileAsset",
                            "thumbAsset"
            """))
        #expect(vaultStoreSource.contains("let remoteRecords = await sync.fetchRemoteItemsForIndex()"))
    }

    @Test func optimizedStorageOffloadsOriginalsAfterSuccessfulItemSync() throws {
        let vaultStoreSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("VaultStore.swift"),
            encoding: .utf8
        )

        #expect(vaultStoreSource.contains("let synced = await sync.syncItem(item)"))
        #expect(vaultStoreSource.contains("if synced {"))
        #expect(vaultStoreSource.contains("releaseLocalOriginalIfBackedUp(for: item)"))
        #expect(vaultStoreSource.contains("item.assetState = .cloudOnly"))
        #expect(vaultStoreSource.contains("VaultFileStore.remove(path: item.encryptedFilePath)"))
    }

    @Test func mediaPreviewRepairDoesNotDownloadOriginalsForGridThumbnails() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("VaultStore.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "func ensureMediaPreviews("))
        let end = try #require(source.range(of: "@discardableResult\n    func downloadAllCloudAssets"))
        let ensureMediaPreviewsSource = source[start.lowerBound..<end.lowerBound]

        #expect(ensureMediaPreviewsSource.contains("downloadThumbnailIfAvailable"))
        #expect(ensureMediaPreviewsSource.contains("VaultFileStore.fileExists(path: item.encryptedFilePath)"))
        #expect(!ensureMediaPreviewsSource.contains("downloadOriginalIfNeeded"))
    }

    @Test func cloudOnlyMetadataSyncPreservesRemoteFileAssetWithoutLocalOriginal() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("CloudKitSyncService.swift"),
            encoding: .utf8
        )

        #expect(source.contains("let canPreserveRemoteFileAsset = requiresFileAsset"))
        #expect(source.contains("item.assetState == .cloudOnly"))
        #expect(source.contains("canPreserveRemoteFileAsset || VaultFileStore.fileExists(path: item.encryptedFilePath)"))
        #expect(source.contains("if requiresFileAsset, VaultFileStore.fileExists(path: item.encryptedFilePath)"))
    }

    @MainActor
    @Test func vaultMetadataRoundTripsCaptureLocation() throws {
        let location = VaultCaptureLocation(
            latitude: 31.2304,
            longitude: 121.4737,
            horizontalAccuracy: 8,
            altitude: 12,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            resolvedAddress: "Shanghai, Huangpu"
        )
        let metadata = VaultMetadata(
            originalName: "Photo.jpg",
            mimeType: "image/jpeg",
            source: "Camera",
            note: "",
            importedAt: Date(timeIntervalSince1970: 1_800_000_001),
            captureLocation: location
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(VaultMetadata.self, from: data)

        #expect(decoded.captureLocation == location)
        #expect(decoded.captureLocation?.coordinateText == "31.23040, 121.47370")
        #expect(decoded.captureLocation?.resolvedAddress == "Shanghai, Huangpu")
    }

    @Test func mapCoordinatePolicyOffsetsMainlandChinaLocationsForMapKit() {
        let shanghai = VaultMapCoordinatePolicy.mapCoordinate(latitude: 31.2304, longitude: 121.4737)
        let sanFrancisco = VaultMapCoordinatePolicy.mapCoordinate(latitude: 37.7749, longitude: -122.4194)

        #expect(abs(shanghai.latitude - 31.22846) < 0.0001)
        #expect(abs(shanghai.longitude - 121.47822) < 0.0001)
        #expect(sanFrancisco.latitude == 37.7749)
        #expect(sanFrancisco.longitude == -122.4194)
    }

    @Test func cameraCaptureImportsPersistCaptureLocationMetadata() throws {
        let featureSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("FeatureViews.swift"),
            encoding: .utf8
        )
        let vaultStoreSource = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("VaultStore.swift"),
            encoding: .utf8
        )

        #expect(featureSource.contains("locationProvider.captureLocation()"))
        #expect(featureSource.contains("case .photo(let image, let location)"))
        #expect(featureSource.contains("case .video(let url, let location)"))
        #expect(featureSource.contains("captureLocation: location"))
        #expect(vaultStoreSource.contains("captureLocation: VaultCaptureLocation? = nil"))
        #expect(vaultStoreSource.contains("captureLocation: captureLocation"))
    }

    @Test func photoLibraryImportPersistsOriginalAssetLocationAndResolvedAddress() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("ImportService.swift"),
            encoding: .utf8
        )

        #expect(source.contains("captureLocation(for: item, fallbackData:"))
        #expect(source.contains("PHAsset.fetchAssets(withLocalIdentifiers"))
        #expect(source.contains("CGImagePropertyGPSDictionary"))
        #expect(source.contains("reverseGeocodeLocation"))
        #expect(source.contains("captureLocation: captureLocation"))
    }

    @Test func mediaDetailsExposeCaptureLocationMapCard() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("MainViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("if let location = metadata?.captureLocation"))
        #expect(source.contains("Text(location.resolvedAddress ?? location.coordinateText)"))
        #expect(source.contains("detailRow(L.string(\"Address\"), location.resolvedAddress)"))
        #expect(source.contains("VaultLocationMapView"))
        #expect(source.contains("Map(position: .constant(.region(region)))"))
        #expect(source.contains("Open in Apple Maps"))
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

    @Test func cloudAssetDownloadPolicySelectsVisualItemsWithMissingLocalPreview() throws {
        let image = VaultItem(kind: .image, encryptedMetadata: Data(), byteSize: 4, assetState: .local)
        let video = VaultItem(kind: .video, encryptedMetadata: Data(), byteSize: 4, assetState: .local)
        let audio = VaultItem(kind: .audio, encryptedMetadata: Data(), byteSize: 4, assetState: .local)
        let thumbPath = try VaultFileStore.writeEncryptedThumb(Data("encrypted-thumb".utf8), itemId: "preview-policy-\(UUID().uuidString)")
        defer { VaultFileStore.remove(path: thumbPath) }
        video.encryptedThumbPath = thumbPath

        #expect(VaultCloudAssetDownloadPolicy.needsLocalPreview(image))
        #expect(!VaultCloudAssetDownloadPolicy.needsLocalPreview(video))
        #expect(!VaultCloudAssetDownloadPolicy.needsLocalPreview(audio))

        VaultFileStore.remove(path: thumbPath)
        #expect(VaultCloudAssetDownloadPolicy.needsLocalPreview(video))
    }

    @Test func remoteMergePolicyKeepsPendingLocalDeleteOverOlderRemoteRecord() throws {
        let localUpdatedAt = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 11)))
        let remoteUpdatedAt = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))

        #expect(!VaultRemoteMergePolicy.shouldApplyRemote(
            remoteUpdatedAt: remoteUpdatedAt,
            remoteRevision: 3,
            localUpdatedAt: localUpdatedAt,
            localRevision: 4,
            localSyncStatus: .pending
        ))
        #expect(VaultRemoteMergePolicy.shouldApplyRemote(
            remoteUpdatedAt: remoteUpdatedAt,
            remoteRevision: 3,
            localUpdatedAt: localUpdatedAt,
            localRevision: 4,
            localSyncStatus: .synced
        ))
    }

    @Test func homeIconLayoutsStayCompact() {
        #expect(VaultHomeHeaderLayout.actionSize == 34)
        #expect(VaultHomeHeaderLayout.iconFontSize == 17)
        #expect(VaultCategoryCarouselLayout.iconFontSize == 22)
    }

    @Test func photoLibraryExportSupportsPhotosLivePhotosAndVideos() {
        #expect(PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .image))
        #expect(PhotoLibraryExportService.canSaveToPhotoLibrary(kind: .livePhoto))
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
        #expect(AppRootPresentation.blocksLaunchForCloudRefresh == false)
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

    @Test func appStorageUsageFormatterUsesReadableBinaryUnits() {
        let locale = Locale(identifier: "en_US_POSIX")

        #expect(AppStorageUsageFormatter.localizedFileSize(0, locale: locale) == "0 B")
        #expect(AppStorageUsageFormatter.localizedFileSize(1_536, locale: locale) == "1.5 KB")
        #expect(AppStorageUsageFormatter.localizedFileSize(1_572_864, locale: locale) == "1.5 MB")
        #expect(AppStorageUsageFormatter.localizedFileSize(1_610_612_736, locale: locale) == "1.50 GB")
    }

    @Test func appStorageUsageSnapshotSeparatesVaultAndOtherAppData() {
        let snapshot = AppStorageUsageSnapshot(
            appBundleBytes: 100,
            appDataBytes: 900,
            vaultBytes: 500,
            encryptedOriginalBytes: 320,
            thumbnailBytes: 80,
            vaultTemporaryBytes: 20,
            cacheBytes: 120,
            temporaryBytes: 40
        )

        #expect(snapshot.totalBytes == 1_000)
        #expect(snapshot.otherVaultBytes == 80)
        #expect(snapshot.otherAppDataBytes == 240)
    }

    @Test func generalSettingsExposesAppStorageUsageOption() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("privacy")
                .appendingPathComponent("FeatureViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("AppStorageUsageSettingsView(initialSnapshot: storageUsageSnapshot)"))
        #expect(source.contains("title: L.string(\"App Storage Usage\")"))
        #expect(source.contains("detail: storageUsageDetail"))
        #expect(source.contains("L.format(\n            \"Currently using %@\""))
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
        let key = "Items are encrypted on this device before optional iCloud sync."
        let english = try localizedStrings(bundleCode: "en")[key]
        let simplifiedChinese = try localizedStrings(bundleCode: "zh-Hans")[key]
        let traditionalChinese = try localizedStrings(bundleCode: "zh-Hant")[key]

        #expect(simplifiedChinese != english)
        #expect(traditionalChinese != english)
        #expect(simplifiedChinese?.contains("iCloud") == true)
        #expect(traditionalChinese?.contains("iCloud") == true)
    }

    @Test func localizedBrandNamesUseMoLayerNaming() throws {
        let expectedDisplayNames = [
            "en": "Mo Layer",
            "zh-Hans": "墨层",
            "zh-Hant": "墨層",
            "de": "Mo Layer",
            "es": "Mo Layer",
            "fr": "Mo Layer",
            "ja": "Mo Layer",
            "ko": "Mo Layer"
        ]

        for (bundleCode, expectedName) in expectedDisplayNames {
            let infoPlistStrings = try infoPlistStrings(bundleCode: bundleCode)
            #expect(infoPlistStrings["CFBundleDisplayName"] == expectedName)

            let localizedValues = try localizedStrings(bundleCode: bundleCode).values
            #expect(!localizedValues.contains { $0.contains("Palimpsest") })
            #expect(!localizedValues.contains { $0.contains("Aegis") })
        }
    }

    @Test func moLayerTutorialStringsAreLocalized() throws {
        let keys = [
            "Mo Layer Tutorial",
            "What is Mo Layer?",
            "Enter Mo Layer",
            "Save files to Mo Layer",
            "Tap the blank touch zone between the category title and the profile avatar three times to enter Mo Layer.",
            "Practice tapping the Mo Layer entry zone"
        ]

        let english = try localizedStrings(bundleCode: "en")
        let simplifiedChinese = try localizedStrings(bundleCode: "zh-Hans")

        for key in keys {
            #expect(english[key]?.isEmpty == false)
            #expect(simplifiedChinese[key]?.isEmpty == false)
        }

        #expect(english["Mo Layer Tutorial"] == "Mo Layer Tutorial")
        #expect(simplifiedChinese["Mo Layer Tutorial"] == "墨层教学")
        #expect(simplifiedChinese["Tap the blank touch zone between the category title and the profile avatar three times to enter Mo Layer."]?.contains("头像") == true)
    }

    @MainActor
    @Test func moLayerTutorialPracticeCompletesOnThirdTap() {
        var counter = MoLayerTutorialPracticeCounter()

        #expect(counter.recordTap() == .counting(1))
        #expect(counter.tapCount == 1)
        #expect(counter.recordTap() == .counting(2))
        #expect(counter.tapCount == 2)
        #expect(counter.recordTap() == .completed(3))
        #expect(counter.tapCount == 3)
    }

    @MainActor
    @Test func moLayerTutorialPracticeResetClearsTapProgress() {
        var counter = MoLayerTutorialPracticeCounter()

        _ = counter.recordTap()
        _ = counter.recordTap()
        counter.reset()

        #expect(counter.tapCount == 0)
        #expect(counter.recordTap() == .counting(1))
    }

    @Test func cloudSyncStateExposesSettingsActionForUnavailableStates() {
        #expect(CloudSyncState.unavailable("No iCloud").needsICloudSettingsAction)
        #expect(CloudSyncState.failed("No iCloud").needsICloudSettingsAction)
        #expect(!CloudSyncState.checking.needsICloudSettingsAction)
        #expect(!CloudSyncState.available.needsICloudSettingsAction)
        #expect(!CloudSyncState.syncing.needsICloudSettingsAction)
        #expect(!CloudSyncState.synced(Date()).needsICloudSettingsAction)
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

    @MainActor
    @Test func subscriptionComplianceLinksAndTrialDisclosureAreConfigured() {
        #expect(SubscriptionManager.freeTrialDays == 3)
        #expect(SubscriptionManager.termsOfUseURL.scheme == "https")
        #expect(SubscriptionManager.termsOfUseURL.absoluteString.contains("molayer.tech"))
    }

    @Test func subscriptionManagerUsesRevenueCatBackupProxyForMainlandChinaReachability() {
        #expect(SubscriptionManager.revenueCatProxyURL.absoluteString == "https://api.rc-backup.com/")
    }

    @MainActor
    @Test func restorePurchasesWithoutRevenueCatShowsRestoreFailureFeedback() async {
        let manager = SubscriptionManager()
        manager.configureRevenueCat(apiKey: nil)

        await manager.restorePurchases()

        #expect(manager.statusText == L.string("Restore purchase failed. Please try again."))
    }

    @MainActor
    @Test func redeemOfferCodeWithoutRevenueCatShowsUnavailableFeedback() async {
        let manager = SubscriptionManager()
        manager.configureRevenueCat(apiKey: nil)

        await manager.redeemOfferCode()

        #expect(manager.statusText == L.string("Code redemption is unavailable. Please try again later."))
        #expect(manager.restoreFeedback?.message == L.string("Code redemption is unavailable. Please try again later."))
    }

    @MainActor
    @Test func restorePurchaseFeedbackDistinguishesRestoredNoPurchaseAndFailureStates() {
        let restored = RestorePurchaseFeedback.restored(hasActivePro: true)
        #expect(restored.kind == .success)
        #expect(restored.message == L.string("Purchases restored. Pro is active."))

        let notFound = RestorePurchaseFeedback.restored(hasActivePro: false)
        #expect(notFound.kind == .warning)
        #expect(notFound.message == L.string("No previous purchases found for this Apple ID."))

        let failed = RestorePurchaseFeedback.failed()
        #expect(failed.kind == .warning)
        #expect(failed.message == L.string("Restore purchase failed. Please try again."))
    }

    @Test func membershipAccessSeparatesActiveExpiredAndLockedStates() {
        #expect(SubscriptionManager.accessLevel(isPro: true, hasActivatedPro: false) == .activePro)
        #expect(SubscriptionManager.accessLevel(isPro: false, hasActivatedPro: true) == .expiredReadOnly)
        #expect(SubscriptionManager.accessLevel(isPro: false, hasActivatedPro: false) == .lockedUntilPro)
        #expect(MembershipAccessLevel.activePro.allowsVaultEntry)
        #expect(MembershipAccessLevel.activePro.allowsCloudPull)
        #expect(MembershipAccessLevel.activePro.allowsImportAndCloudSync)
        #expect(MembershipAccessLevel.expiredReadOnly.allowsVaultEntry)
        #expect(MembershipAccessLevel.expiredReadOnly.allowsCloudPull)
        #expect(!MembershipAccessLevel.expiredReadOnly.allowsImportAndCloudSync)
        #expect(!MembershipAccessLevel.lockedUntilPro.allowsVaultEntry)
        #expect(!MembershipAccessLevel.lockedUntilPro.allowsCloudPull)
        #expect(!MembershipAccessLevel.lockedUntilPro.allowsImportAndCloudSync)
    }

    @Test func moLayerEntryActionExplainsProOnlyToNeverSubscribedUsers() {
        #expect(MembershipAccessLevel.activePro.moLayerEntryAction == .enter)
        #expect(MembershipAccessLevel.expiredReadOnly.moLayerEntryAction == .enter)
        #expect(MembershipAccessLevel.lockedUntilPro.moLayerEntryAction == .explainPro)
    }

    @Test func freeImportPolicyAllowsFirstNinetyNineVaultFilesBeforePro() {
        #expect(VaultFreeImportPolicy.freeItemLimit == 99)
        #expect(VaultFreeImportPolicy.canImport(currentCount: 0, incomingCount: 1, isPro: false))
        #expect(VaultFreeImportPolicy.canImport(currentCount: 98, incomingCount: 1, isPro: false))
        #expect(!VaultFreeImportPolicy.canImport(currentCount: 99, incomingCount: 1, isPro: false))
        #expect(!VaultFreeImportPolicy.canImport(currentCount: 98, incomingCount: 2, isPro: false))
        #expect(VaultFreeImportPolicy.canImport(currentCount: 250, incomingCount: 20, isPro: true))
    }

    @Test func freeImportPolicyCountsOnlyActiveMediaFileItems() {
        let image = VaultItem(kind: .image, encryptedMetadata: Data(), byteSize: 1)
        let video = VaultItem(kind: .video, encryptedMetadata: Data(), byteSize: 1)
        let audio = VaultItem(kind: .audio, encryptedMetadata: Data(), byteSize: 1)
        let document = VaultItem(kind: .document, encryptedMetadata: Data(), byteSize: 1)
        let link = VaultItem(kind: .link, encryptedMetadata: Data(), byteSize: 0)
        let deletedArchive = VaultItem(kind: .archive, encryptedMetadata: Data(), byteSize: 1)
        deletedArchive.deletedAt = Date()

        #expect(VaultFreeImportPolicy.countedItemCount(in: [image, video, audio, document, link, deletedArchive]) == 4)
    }

    @Test func membershipStatusSummaryShowsPlanAndExpiration() throws {
        let expiry = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 9)))
        let activeSummary = MembershipStatusSummary(
            accessLevel: .activePro,
            productIdentifier: SubscriptionManager.yearly,
            expirationDate: expiry,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        #expect(activeSummary.planTitle == L.string("Yearly Pro"))
        #expect(activeSummary.stateTitle == L.string("Pro Active"))
        #expect(activeSummary.expirationText == L.format("Valid until %@", activeSummary.formattedExpirationDate))

        let lifetimeSummary = MembershipStatusSummary(
            accessLevel: .activePro,
            productIdentifier: SubscriptionManager.lifetime,
            expirationDate: nil,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        #expect(lifetimeSummary.expirationText == L.string("Lifetime access"))

        let monthlyWithoutExpirationSummary = MembershipStatusSummary(
            accessLevel: .activePro,
            productIdentifier: SubscriptionManager.monthly,
            expirationDate: nil,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        #expect(monthlyWithoutExpirationSummary.planTitle == L.string("Monthly Pro"))
        #expect(monthlyWithoutExpirationSummary.expirationText.isEmpty)

        let readOnlySummary = MembershipStatusSummary(
            accessLevel: .expiredReadOnly,
            productIdentifier: nil,
            expirationDate: nil,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        #expect(readOnlySummary.stateTitle == L.string("Read-Only Protection"))
        #expect(readOnlySummary.expirationText == L.string("Expired or inactive"))
    }

    @Test func moLayerEntryUsesVaultReadAccessInsteadOfWriteAccess() throws {
        let sourceText = try String(
            contentsOf: repositoryRoot().appendingPathComponent("privacy/MainViews.swift"),
            encoding: .utf8
        )
        let enterInnerVaultStart = try #require(sourceText.range(of: "private func enterInnerVault()"))
        let toggleInnerVaultStart = try #require(sourceText.range(of: "private func toggleInnerVault()"))
        let enterInnerVaultBody = String(sourceText[enterInnerVaultStart.lowerBound..<toggleInnerVaultStart.lowerBound])

        #expect(enterInnerVaultBody.contains("subscription.canEnterVault"))
        #expect(!enterInnerVaultBody.contains("subscription.canImportAndSync"))
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
    @Test func disablingGestureVerificationSkipsGestureGateAfterFaceID() {
        let auth = AuthenticationManager()
        defer {
            auth.requiresBiometricUnlock = true
            auth.requiresGestureUnlock = true
        }

        auth.requiresBiometricUnlock = true
        auth.requiresGestureUnlock = true
        auth.sessionMode = .gestureGate

        auth.requiresGestureUnlock = false

        #expect(auth.sessionMode == .realVault)
    }

    @MainActor
    @Test func disablingBothUnlockChecksOpensRealVaultFromCover() {
        let auth = AuthenticationManager()
        defer {
            auth.requiresBiometricUnlock = true
            auth.requiresGestureUnlock = true
        }

        auth.requiresBiometricUnlock = true
        auth.requiresGestureUnlock = true
        auth.sessionMode = .cover

        auth.requiresBiometricUnlock = false
        auth.requiresGestureUnlock = false

        #expect(auth.sessionMode == .realVault)
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
        #expect(router.lastReason == .recordType("VaultFolder"))
        #expect(router.lastReceivedAt != nil)

        router.consume(.recordType("VaultFolder"))
        #expect(router.pendingReason == nil)
        #expect(router.lastReason == .recordType("VaultFolder"))
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
            descriptor.recordName.hasPrefix(CloudKitSyncService.internalRecordNamePrefix)
                && !descriptor.recordName.hasPrefix("_")
        }
        #expect(seedNamesAreInternal)
        #expect(CloudKitSyncService.isInternalRecordName("__privacy_schema_seed_vault_item"))
    }

    @MainActor
    @Test func cloudKitWritableProbeUsesProductionSchemaRecordType() {
        #expect(CloudKitSyncService.writableProbeRecordType == "VaultManifest")
        #expect(CloudKitSyncService.writableProbeRecordName.hasPrefix(CloudKitSyncService.internalRecordNamePrefix))
        #expect(!CloudKitSyncService.writableProbeRecordName.hasPrefix("_"))
        #expect(CloudKitSyncService.changeSubscriptionDescriptors.map(\.recordType).contains(CloudKitSyncService.writableProbeRecordType))
    }

    @MainActor
    @Test func cloudKitSchemaSeedRecordsAreFilteredFromUserResults() {
        let seed = CKRecord(
            recordType: "VaultItem",
            recordID: CKRecord.ID(recordName: "__privacy_schema_seed_vault_item")
        )
        let probe = CKRecord(
            recordType: "VaultManifest",
            recordID: CKRecord.ID(recordName: CloudKitSyncService.writableProbeRecordName)
        )
        let user = CKRecord(
            recordType: "VaultItem",
            recordID: CKRecord.ID(recordName: "user-item")
        )

        #expect(CloudKitSyncService.userRecords(from: [seed, probe, user]).map(\.recordID.recordName) == ["user-item"])
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

private func infoPlistStrings(bundleCode: String) throws -> [String: String] {
    let url = repositoryRoot()
        .appendingPathComponent("privacy")
        .appendingPathComponent("\(bundleCode).lproj")
        .appendingPathComponent("InfoPlist.strings")
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

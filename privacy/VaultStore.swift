import Combine
import AVFoundation
import CloudKit
import CryptoKit
import Foundation
import ImageIO
import OSLog
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct VaultThumbnailLoadRequest: Sendable {
    let cacheKey: String
    let encryptedThumbPath: String
    let encryptedFileKey: Data
    let rootKey: SymmetricKey

    nonisolated init(
        cacheKey: String,
        encryptedThumbPath: String,
        encryptedFileKey: Data,
        rootKey: SymmetricKey
    ) {
        self.cacheKey = cacheKey
        self.encryptedThumbPath = encryptedThumbPath
        self.encryptedFileKey = encryptedFileKey
        self.rootKey = rootKey
    }
}

actor VaultThumbnailDataLoader {
    nonisolated static let maximumConcurrentLoads = 3

    private var activeLoadCount = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func decryptedData(for request: VaultThumbnailLoadRequest) throws -> Data {
        try Self.decryptData(for: request)
    }

    func image(for request: VaultThumbnailLoadRequest) async -> UIImage? {
        if let task = inFlight[request.cacheKey] {
            return await task.value
        }

        let task = Task { await performLoad(request) }
        inFlight[request.cacheKey] = task
        let image = await task.value
        inFlight[request.cacheKey] = nil
        return image
    }

    private func performLoad(_ request: VaultThumbnailLoadRequest) async -> UIImage? {
        await acquireSlot()
        defer { releaseSlot() }
        return await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                do {
                    let data = try Self.decryptData(for: request)
                    let options = [
                        kCGImageSourceShouldCache: true,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary
                    guard let source = CGImageSourceCreateWithData(data as CFData, options),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) else {
                        return nil
                    }
                    return UIImage(cgImage: cgImage)
                } catch {
                    return nil
                }
            }
        }.value
    }

    private func acquireSlot() async {
        if activeLoadCount < Self.maximumConcurrentLoads {
            activeLoadCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            slotWaiters.append(continuation)
        }
    }

    private func releaseSlot() {
        if slotWaiters.isEmpty {
            activeLoadCount = max(0, activeLoadCount - 1)
        } else {
            slotWaiters.removeFirst().resume()
        }
    }

    nonisolated private static func decryptData(for request: VaultThumbnailLoadRequest) throws -> Data {
        try Task.checkCancellation()
        let fileKey = try VaultCryptoService.unwrapFileKey(
            request.encryptedFileKey,
            rootKey: request.rootKey
        )
        let encrypted = try VaultFileStore.read(path: request.encryptedThumbPath)
        try Task.checkCancellation()
        return try VaultCryptoService.decrypt(encrypted, using: fileKey)
    }
}

enum VaultPreviewFileCachePolicy {
    nonisolated static func cacheKey(
        itemID: String,
        encryptedFilePath: String,
        encryptedFileKey: Data,
        updatedAt: Date
    ) -> String {
        "\(itemID)|\(encryptedFilePath)|\(encryptedFileKey.base64EncodedString())|\(updatedAt.timeIntervalSince1970)"
    }
}

struct VaultPreviewFileLoadRequest: Sendable {
    let cacheKey: String
    let fileName: String
    let encryptedFilePath: String
    let encryptedFileKey: Data
    let rootKey: SymmetricKey
}

actor VaultPreviewFileLoader {
    private var cachedURLs: [String: URL] = [:]
    private var inFlight: [String: Task<URL, Error>] = [:]

    func url(for request: VaultPreviewFileLoadRequest) async throws -> URL {
        if let cachedURL = cachedURLs[request.cacheKey],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        if let task = inFlight[request.cacheKey] {
            return try await task.value
        }

        let task = Task.detached(priority: .userInitiated) {
            let fileKey = try VaultCryptoService.unwrapFileKey(
                request.encryptedFileKey,
                rootKey: request.rootKey
            )
            let encrypted = try VaultFileStore.read(path: request.encryptedFilePath)
            try Task.checkCancellation()
            let decrypted = try VaultCryptoService.decrypt(encrypted, using: fileKey)
            try Task.checkCancellation()
            return try VaultFileStore.temporaryPlainURL(fileName: request.fileName, data: decrypted)
        }
        inFlight[request.cacheKey] = task

        do {
            let url = try await task.value
            cachedURLs[request.cacheKey] = url
            inFlight[request.cacheKey] = nil
            return url
        } catch {
            inFlight[request.cacheKey] = nil
            throw error
        }
    }
}

enum RemoteVaultRestoreCheck: Equatable {
    case noRemoteVault
    case needsRecoveryKey
    case restoredAutomatically(CloudAssetDownloadSummary)
    case failed(String)
}

struct CloudAssetDownloadSummary: Equatable {
    var indexedItems = 0
    var total = 0
    var succeeded = 0
    var failed = 0
    var failureMessages: [String] = []

    var displayText: String {
        if total == 0 {
            if indexedItems > 0 {
                return L.format("%d encrypted item(s) restored from iCloud. Originals download when opened.", indexedItems)
            }
            return L.string("iCloud backup restored. No encrypted files needed downloading.")
        }
        if failed == 0 {
            return L.format("%d encrypted file(s) downloaded from iCloud.", succeeded)
        }
        return L.format("%d encrypted file(s) downloaded, %d failed.", succeeded, failed)
    }
}

enum VaultCloudToLocalSyncPurpose {
    case routineSync
    case reinstallRestore
}

enum VaultCloudToLocalSyncPolicy {
    nonisolated static let automaticDownloadsPreviews = false
    nonisolated static let manualRefreshDownloadsOriginals = false
    static let syncedHomeCategories: [VaultCategory] = [.album, .audio, .documents]

    nonisolated static func downloadsOriginals(
        purpose: VaultCloudToLocalSyncPurpose,
        explicitOverride: Bool?
    ) -> Bool {
        if let explicitOverride {
            return explicitOverride
        }
        switch purpose {
        case .routineSync:
            return false
        case .reinstallRestore:
            return true
        }
    }
}

enum VaultCloudMetadataClassification: Equatable {
    case readable
    case incompatiblePayload
    case wrongRootKey
}

enum VaultCloudMetadataInspector {
    static func classify(_ encryptedMetadata: Data, using rootKey: SymmetricKey) -> VaultCloudMetadataClassification {
        let decrypted: Data
        do {
            decrypted = try VaultCryptoService.decrypt(encryptedMetadata, using: rootKey)
        } catch {
            return .wrongRootKey
        }

        do {
            _ = try JSONDecoder().decode(VaultMetadata.self, from: decrypted)
            return .readable
        } catch {
            return .incompatiblePayload
        }
    }
}

enum VaultRemoteRootKeyPolicy {
    nonisolated static func shouldRestorePackagedKey(
        localKeyOpensManifest: Bool,
        recoveryKeyOpensPackage: Bool
    ) -> Bool {
        !localKeyOpensManifest && recoveryKeyOpensPackage
    }
}

struct VaultRecoveryCandidateScore: Equatable, Sendable {
    let id: String
    let readableItemCount: Int

    nonisolated init(id: String, readableItemCount: Int) {
        self.id = id
        self.readableItemCount = readableItemCount
    }
}

enum VaultRecoverySelectionPolicy {
    nonisolated static func select(candidates: [VaultRecoveryCandidateScore]) -> VaultRecoveryCandidateScore? {
        guard let highestCount = candidates.map(\.readableItemCount).max(), highestCount > 0 else {
            return nil
        }
        let bestCandidates = candidates.filter { $0.readableItemCount == highestCount }
        guard bestCandidates.count == 1 else { return nil }
        return bestCandidates[0]
    }

    nonisolated static func shouldRequestRecovery(
        readableItemCount: Int,
        wrongRootKeyCount: Int
    ) -> Bool {
        wrongRootKeyCount > readableItemCount
    }
}

private struct VaultCloudIndexPullSummary {
    var fetched = 0
    var indexed = 0
    var missingIdentity = 0
    var incompatiblePayload = 0
    var wrongRootKey = 0

    var skipped: Int {
        missingIdentity + incompatiblePayload + wrongRootKey
    }
}

private struct VaultRecoveryLocalCleanup {
    let items: [VaultItem]
    let folders: [VaultFolder]
    let notes: [DecoyNoteRecord]
}

enum VaultOptimizedStoragePolicy {
    static let isEnabledByDefault = true
    static let maxLocalOriginalCacheBytes: Int64 = 300 * 1024 * 1024
    static let targetLocalOriginalCacheBytes: Int64 = 200 * 1024 * 1024
    static let immediateReleaseByteThreshold: Int64 = 25 * 1024 * 1024
    static let lowDiskFreeBytes: Int64 = 1 * 1024 * 1024 * 1024
    static let accessTimestampUpdateInterval: TimeInterval = 15 * 60

    static func shouldReleaseAfterSuccessfulSync(_ item: VaultItem) -> Bool {
        isEnabledByDefault
            && item.deletedAt == nil
            && item.kind != .link
            && item.syncStatus == .synced
            && item.assetState == .local
            && item.byteSize >= immediateReleaseByteThreshold
    }
}

private enum VaultOriginalReleaseTrigger {
    case successfulSync
    case cachePressure
    case manual
}

enum VaultCloudAssetDownloadPolicy {
    static func shouldDownload(_ item: VaultItem) -> Bool {
        item.deletedAt == nil
            && item.kind != .link
            && (item.assetState != .local || !VaultFileStore.fileExists(path: item.encryptedFilePath))
    }

    static func needsLocalPreview(_ item: VaultItem) -> Bool {
        item.deletedAt == nil
            && item.kind.isVisualMedia
            && (item.encryptedThumbPath?.isEmpty != false || !VaultFileStore.fileExists(path: item.encryptedThumbPath))
    }
}

enum VaultMediaPreviewRepairPolicy {
    nonisolated static func needsVideoDuration(
        kind: VaultItemKind,
        storedDuration: Double?,
        hasLocalOriginal: Bool
    ) -> Bool {
        kind == .video && storedDuration == nil && hasLocalOriginal
    }
}

struct VaultImportPreparedItem {
    let itemId: String
    let encryptedFilePath: String
    let encryptedThumbPath: String?
    let encryptedMetadata: Data
    let encryptedFileKey: Data
    let importFingerprint: String?
}

enum VaultImportResult: Equatable {
    case imported
    case skippedDuplicate
    case failed
}

enum VaultImportBatchPolicy {
    static let saveInterval = 10

    static func shouldSave(afterImportedCount importedCount: Int) -> Bool {
        importedCount > 0 && importedCount % saveInterval == 0
    }
}

enum VaultImportArtifactBuilder {
    static func fingerprint(for data: Data, kind: VaultItemKind) async -> String? {
        switch kind {
        case .link:
            return nil
        case .image, .livePhoto, .video, .audio, .document, .archive, .other:
            return VaultImportFingerprint.digest(for: data)
        }
    }

    static func prepare(
        data: Data,
        originalName: String,
        mimeType: String,
        source: String,
        kind: VaultItemKind,
        importFingerprint: String?,
        capturedAt: Date? = nil,
        captureLocation: VaultCaptureLocation? = nil,
        itemID: String = UUID().uuidString,
        rootKeyOverride: SymmetricKey? = nil
    ) async throws -> VaultImportPreparedItem {
        let rootKey = try rootKeyOverride ?? VaultCryptoService.ensureRootKey()
        let fileKey = VaultCryptoService.newFileKey()
        let itemId = itemID
        let encryptedFilePath = try await Task.detached(priority: .userInitiated) {
            let encrypted = try VaultCryptoService.encrypt(data, using: fileKey)
            return try VaultFileStore.writeEncryptedObject(encrypted, itemId: itemId)
        }.value

        let thumbData = await makeThumbnailData(
            from: data,
            kind: kind,
            originalName: originalName,
            mimeType: mimeType
        )
        let encryptedThumbPath: String?
        if let thumbData {
            let encryptedThumb = try VaultCryptoService.encrypt(thumbData, using: fileKey)
            encryptedThumbPath = try VaultFileStore.writeEncryptedThumb(encryptedThumb, itemId: itemId)
        } else {
            encryptedThumbPath = nil
        }

        let metadata = VaultMetadata(
            originalName: originalName,
            mimeType: mimeType,
            source: source,
            note: "",
            importedAt: Date(),
            remoteURL: nil,
            originalExtension: (originalName as NSString).pathExtension,
            capturedAt: capturedAt,
            captureLocation: captureLocation,
            mediaDurationSeconds: await mediaDurationSeconds(
                from: data,
                kind: kind,
                preferredExtension: videoFileExtension(originalName: originalName, mimeType: mimeType)
            )
        )
        let encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
        let encryptedFileKey = try VaultCryptoService.wrapFileKey(fileKey, rootKey: rootKey)

        return VaultImportPreparedItem(
            itemId: itemId,
            encryptedFilePath: encryptedFilePath,
            encryptedThumbPath: encryptedThumbPath,
            encryptedMetadata: encryptedMetadata,
            encryptedFileKey: encryptedFileKey,
            importFingerprint: importFingerprint
        )
    }

    private static func makeThumbnailData(
        from data: Data,
        kind: VaultItemKind,
        originalName: String,
        mimeType: String
    ) async -> Data? {
        switch kind {
        case .image:
            return await downsampleThumbnail(data)
        case .livePhoto:
            guard let package = try? PropertyListDecoder().decode(LivePhotoPackage.self, from: data) else { return nil }
            return await downsampleThumbnail(package.stillData)
        case .video:
            return await makeVideoThumbnailData(
                from: data,
                preferredExtension: videoFileExtension(originalName: originalName, mimeType: mimeType)
            )
        default:
            return nil
        }
    }

    private static func downsampleThumbnail(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
        }.value
    }

    private static func makeVideoThumbnailData(from data: Data, preferredExtension: String?) async -> Data? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension ?? "mov")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let asset = AVURLAsset(url: temporaryURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            for time in videoThumbnailTimes {
                if let image = try? await generateImage(with: generator, at: time),
                   let data = renderThumbnailData(from: UIImage(cgImage: image)) {
                    return data
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private static var videoThumbnailTimes: [CMTime] {
        [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime(seconds: 1, preferredTimescale: 600)
        ]
    }

    nonisolated static func mediaDurationSeconds(from data: Data, kind: VaultItemKind, preferredExtension: String?) async -> Double? {
        guard kind == .video else { return nil }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension ?? "mov")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let asset = AVURLAsset(url: temporaryURL)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }

    private static func videoFileExtension(originalName: String, mimeType: String) -> String? {
        let nameExtension = (originalName as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameExtension.isEmpty {
            return nameExtension.lowercased()
        }

        let mimeExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
        return mimeExtension?.isEmpty == false ? mimeExtension : nil
    }

    private static func generateImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    private static func renderThumbnailData(from image: UIImage) -> Data? {
        let targetSize = CGSize(width: 360, height: 360)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.jpegData(withCompressionQuality: 0.72) { _ in
            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (targetSize.width - size.width) / 2, y: (targetSize.height - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}

@MainActor
final class VaultStore: ObservableObject {
    static let innerVaultFolderId = "system.innerVault"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "VaultStore")
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private let thumbnailDataLoader = VaultThumbnailDataLoader()
    private let previewFileLoader = VaultPreviewFileLoader()
    private var thumbnailRootKey: SymmetricKey?
    private var mediaCacheGeneration: UInt = 0
    private var metadataCache: [String: (identity: String, metadata: VaultMetadata)] = [:]
    private var thumbnailDownloadTasks: [String: Task<Bool, Never>] = [:]
    private var originalDownloadTasks: [String: Task<Void, Error>] = [:]
    private var routineCloudToLocalSyncTasks: [Bool: Task<CloudAssetDownloadSummary, Never>] = [:]
    @Published var lastError: String?
    @Published var restoreStatusMessage: String?
    @Published private(set) var allowsVaultWrites = false
    @Published private(set) var requiresVaultRecovery = false
    @Published private(set) var cloudIndexRevision = 0

    func setWriteAccess(_ isAllowed: Bool) {
        allowsVaultWrites = isAllowed
    }

    func clearDecryptedMediaCaches() {
        mediaCacheGeneration &+= 1
        thumbnailCache.removeAllObjects()
        metadataCache.removeAll(keepingCapacity: false)
        thumbnailRootKey = nil
    }

    #if DEBUG
    func installPerformanceFixturesIfRequested(context: ModelContext) async {
        guard ProcessInfo.processInfo.arguments.contains("-ui-performance-fixtures") else { return }
        do {
            let existingItems = try context.fetch(FetchDescriptor<VaultItem>())
            guard !existingItems.contains(where: { $0.id.hasPrefix("__performance_fixture_") }) else {
                return
            }

            let rootKey = try VaultCryptoService.ensureRootKey()
            let fileKey = VaultCryptoService.newFileKey()
            let wrappedFileKey = try VaultCryptoService.wrapFileKey(fileKey, rootKey: rootKey)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
            let image = renderer.image { context in
                UIColor(red: 0.08, green: 0.36, blue: 0.64, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
                UIColor(red: 0.12, green: 0.82, blue: 0.70, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 54, y: 54, width: 132, height: 132))
            }
            guard let thumbnailData = image.jpegData(compressionQuality: 0.78) else { return }
            let encryptedThumbnail = try VaultCryptoService.encrypt(thumbnailData, using: fileKey)
            let sharedThumbnailPath = try VaultFileStore.writeEncryptedThumb(
                encryptedThumbnail,
                itemId: "__performance_fixture_shared"
            )
            let imageMetadata = VaultMetadata(
                originalName: "Performance Fixture.jpg",
                mimeType: "image/jpeg",
                source: "DEBUG",
                note: "",
                importedAt: Date(),
                originalExtension: "jpg"
            )
            let encryptedImageMetadata = try VaultCryptoService.encryptCodable(imageMetadata, using: rootKey)
            let baseDate = Date()

            for index in 0..<600 {
                let item = VaultItem(
                    id: "__performance_fixture_image_\(index)",
                    kind: .image,
                    encryptedThumbPath: sharedThumbnailPath,
                    encryptedMetadata: encryptedImageMetadata,
                    encryptedFileKey: wrappedFileKey,
                    byteSize: 0,
                    assetState: .cloudOnly
                )
                item.createdAt = baseDate.addingTimeInterval(-Double(index + 1))
                item.updatedAt = item.createdAt
                item.syncStatus = .synced
                context.insert(item)
            }

            let videoSeedURL = VaultFileStore.tempDirectory.appendingPathComponent("performance-seed.mp4")
            if let videoData = try? Data(contentsOf: videoSeedURL) {
                let videoID = "__performance_fixture_video"
                let encryptedVideo = try VaultCryptoService.encrypt(videoData, using: fileKey)
                let videoPath = try VaultFileStore.writeEncryptedObject(encryptedVideo, itemId: videoID)
                let videoMetadata = VaultMetadata(
                    originalName: "Performance Fixture.mp4",
                    mimeType: "video/mp4",
                    source: "DEBUG",
                    note: "",
                    importedAt: baseDate,
                    originalExtension: "mp4",
                    mediaDurationSeconds: 6
                )
                let videoItem = VaultItem(
                    id: videoID,
                    kind: .video,
                    encryptedFilePath: videoPath,
                    encryptedThumbPath: sharedThumbnailPath,
                    encryptedMetadata: try VaultCryptoService.encryptCodable(videoMetadata, using: rootKey),
                    encryptedFileKey: wrappedFileKey,
                    byteSize: Int64(videoData.count),
                    assetState: .local
                )
                videoItem.createdAt = baseDate.addingTimeInterval(1)
                videoItem.updatedAt = videoItem.createdAt
                videoItem.syncStatus = .synced
                context.insert(videoItem)
            }

            try context.save()
            logger.info("Installed DEBUG media performance fixtures itemCount=600")
        } catch {
            logger.error("DEBUG media performance fixture install failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    func hasLocalVaultData(context: ModelContext) -> Bool {
        do {
            var manifestDescriptor = FetchDescriptor<VaultManifest>()
            manifestDescriptor.fetchLimit = 1
            if try !context.fetch(manifestDescriptor).isEmpty {
                return true
            }

            var itemDescriptor = FetchDescriptor<VaultItem>()
            itemDescriptor.fetchLimit = 1
            if try !context.fetch(itemDescriptor).isEmpty {
                return true
            }
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func requireWriteAccess() -> Bool {
        guard allowsVaultWrites else {
            lastError = L.string("Renew Pro to add, edit, delete, or sync vault content.")
            return false
        }
        return true
    }

    func bootstrap(
        context: ModelContext,
        sync: CloudKitSyncService,
        allowsCloudSync: Bool = true,
        allowsCloudWrite: Bool? = nil
    ) async {
        let canWriteCloud = allowsCloudWrite ?? allowsCloudSync
        do {
            try VaultFileStore.prepareDirectories()
            try repairStoredFileReferences(context: context)
            try await repairMissingVideoThumbnails(context: context)

            var descriptor = FetchDescriptor<VaultManifest>()
            descriptor.fetchLimit = 1
            if try context.fetch(descriptor).isEmpty {
                if allowsCloudSync {
                    let result = await checkForRemoteVaultRestore(context: context, sync: sync)
                    switch result {
                    case .restoredAutomatically, .needsRecoveryKey, .failed:
                        return
                    case .noRemoteVault:
                        break
                    }
                }
                // Another launch task may have restored the manifest while we awaited iCloud.
                if try context.fetch(descriptor).isEmpty {
                    let rootKey = try VaultCryptoService.ensureRootKey()
                    let manifest = try makeLocalManifest(rootKey: rootKey)
                    context.insert(manifest)
                    try context.save()
                    if canWriteCloud { _ = await sync.syncManifest(manifest) }
                    try? context.save()
                }
            }

            await syncPendingChanges(context: context, sync: sync, allowsCloudSync: canWriteCloud)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restoreRootKeyFromCloud(recoveryKey: String, context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        do {
            let manifestCandidates = await sync.fetchRemoteManifestCandidates()
            guard !manifestCandidates.isEmpty else {
                lastError = L.string("No iCloud recovery package was found.")
                return false
            }

            let remoteRecords = await sync.fetchRemoteItemsForIndex()
            var recoveredKeys: [String: SymmetricKey] = [:]
            var candidateRecords: [String: CKRecord] = [:]
            var scores: [VaultRecoveryCandidateScore] = []

            for record in manifestCandidates {
                guard let package = record["encryptedRootKeyPackage"] as? Data,
                      !package.isEmpty,
                      let candidateKey = try? VaultCryptoService.previewRootKey(
                        from: package,
                        recoveryKey: recoveryKey
                      ) else {
                    continue
                }
                if let encryptedName = record["encryptedVaultName"] as? Data,
                   !encryptedName.isEmpty,
                   (try? VaultCryptoService.decryptString(encryptedName, using: candidateKey)) == nil {
                    continue
                }

                let id = record.recordID.recordName
                let readableItemCount = remoteRecords.reduce(into: 0) { count, itemRecord in
                    guard let encryptedMetadata = itemRecord["encryptedMetadata"] as? Data else { return }
                    if VaultCloudMetadataInspector.classify(encryptedMetadata, using: candidateKey) == .readable {
                        count += 1
                    }
                }
                recoveredKeys[id] = candidateKey
                candidateRecords[id] = record
                scores.append(VaultRecoveryCandidateScore(id: id, readableItemCount: readableItemCount))
            }

            guard let selected = VaultRecoverySelectionPolicy.select(candidates: scores),
                  let rootKey = recoveredKeys[selected.id],
                  let remoteManifest = candidateRecords[selected.id] else {
                lastError = L.string("The recovery key did not identify one unique iCloud vault. No local or iCloud data was changed.")
                return false
            }

            let localCleanup = try validateLocalStoreForRecoveredRootKey(rootKey, context: context)
            try VaultCryptoService.installRootKey(rootKey, recoveryKey: recoveryKey)
            localCleanup.items.forEach(context.delete)
            localCleanup.folders.forEach(context.delete)
            localCleanup.notes.forEach(context.delete)
            let existingManifests = try context.fetch(FetchDescriptor<VaultManifest>())
            for manifest in existingManifests {
                context.delete(manifest)
            }
            let manifest = makeManifest(from: remoteManifest)
            manifest.syncStatus = .synced
            context.insert(manifest)
            try context.save()
            clearDecryptedMediaCaches()
            let summary = await syncCloudToLocal(
                context: context,
                sync: sync,
                allowsCloudWrite: false,
                purpose: .reinstallRestore,
                downloadsOriginals: false
            )
            requiresVaultRecovery = false
            restoreStatusMessage = L.format(
                "%d encrypted item(s) restored from the selected iCloud vault. Originals download when opened.",
                max(selected.readableItemCount, summary.indexedItems)
            )
            sync.appendLog(
                "Selected one VaultManifest recovery candidate record=\(selected.id) readableItems=\(selected.readableItemCount) cloudWrite=false"
            )
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private var remoteRestoreTask: Task<RemoteVaultRestoreCheck, Never>?

    func checkForRemoteVaultRestore(context: ModelContext, sync: CloudKitSyncService) async -> RemoteVaultRestoreCheck {
        if let remoteRestoreTask { return await remoteRestoreTask.value }
        let task = Task { @MainActor in
            await self.performRemoteVaultRestore(context: context, sync: sync)
        }
        remoteRestoreTask = task
        defer { remoteRestoreTask = nil }
        return await task.value
    }

    private func performRemoteVaultRestore(context: ModelContext, sync: CloudKitSyncService) async -> RemoteVaultRestoreCheck {
        do {
            var descriptor = FetchDescriptor<VaultManifest>()
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).isEmpty else {
                return .noRemoteVault
            }

            guard let remoteManifest = await sync.fetchRemoteManifest() else {
                if let message = sync.lastSyncError { return .failed(message) }
                return .noRemoteVault
            }

            if try restoreRemoteManifestUsingAvailableKey(remoteManifest, context: context) {
                restoreStatusMessage = L.string("Existing iCloud vault found. Restoring encrypted index...")
                let summary = await syncCloudToLocal(
                    context: context,
                    sync: sync,
                    allowsCloudWrite: false,
                    purpose: .reinstallRestore,
                    downloadsOriginals: false
                )
                restoreStatusMessage = summary.displayText
                return .restoredAutomatically(summary)
            }

            lastError = L.string("An existing iCloud vault was found. Restore it with iCloud Keychain or your recovery key before creating a new vault.")
            restoreStatusMessage = lastError
            return .needsRecoveryKey
        } catch {
            lastError = error.localizedDescription
            restoreStatusMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func importData(
        _ data: Data,
        originalName: String,
        mimeType: String,
        source: String,
        kind: VaultItemKind,
        context: ModelContext,
        sync: CloudKitSyncService,
        folderId: String? = nil,
        syncAfterImport: Bool = true,
        saveImmediately: Bool = true,
        captureLocation: VaultCaptureLocation? = nil
    ) async -> VaultImportResult {
        guard requireWriteAccess() else { return .failed }
        do {
            let importFingerprint = await VaultImportArtifactBuilder.fingerprint(for: data, kind: kind)
            if try isDuplicateImport(importFingerprint, context: context) {
                lastError = L.string("This item has already been imported.")
                return .skippedDuplicate
            }

            let reservation = try VaultStorageQuota.reserve(bytes: Int64(data.count), context: context)
            defer { VaultStorageQuota.release(reservation) }
            let prepared = try await VaultImportArtifactBuilder.prepare(
                data: data,
                originalName: originalName,
                mimeType: mimeType,
                source: source,
                kind: kind,
                importFingerprint: importFingerprint,
                captureLocation: captureLocation
            )

            let item = VaultItem(
                id: prepared.itemId,
                kind: kind,
                encryptedFilePath: prepared.encryptedFilePath,
                encryptedThumbPath: prepared.encryptedThumbPath,
                encryptedMetadata: prepared.encryptedMetadata,
                encryptedFileKey: prepared.encryptedFileKey,
                byteSize: Int64(data.count),
                folderId: folderId,
                importFingerprint: prepared.importFingerprint
            )
            context.insert(item)
            try context.save()
            VaultStorageQuota.release(reservation)
            logger.info("Imported item \(prepared.itemId, privacy: .public), kind \(kind.rawValue, privacy: .public), file \(prepared.encryptedFilePath, privacy: .public), thumb \(prepared.encryptedThumbPath ?? "none", privacy: .public)")
            if syncAfterImport {
                let synced = await sync.syncItem(item)
                if synced {
                    releaseLocalOriginalIfBackedUp(for: item)
                    _ = offloadOriginalsIfNeeded(context: context)
                }
                try? context.save()
            }
            return .imported
        } catch {
            lastError = error.localizedDescription
            return .failed
        }
    }

    private func isDuplicateImport(_ importFingerprint: String?, context: ModelContext) throws -> Bool {
        guard let importFingerprint else { return false }
        var descriptor = FetchDescriptor<VaultItem>(predicate: #Predicate { $0.deletedAt == nil && $0.importFingerprint == importFingerprint })
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }

    func importLink(
        _ url: URL,
        title: String?,
        source: String,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let displayName = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : url.host() ?? url.absoluteString
            let metadata = VaultMetadata(
                originalName: displayName,
                mimeType: "text/uri-list",
                source: source,
                note: "",
                importedAt: Date(),
                remoteURL: url.absoluteString,
                originalExtension: nil
            )
            let encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
            let item = VaultItem(
                kind: .link,
                encryptedMetadata: encryptedMetadata,
                encryptedFileKey: Data(),
                byteSize: 0,
                assetState: .local
            )
            context.insert(item)
            try context.save()
            _ = await sync.syncItem(item)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func metadata(for item: VaultItem) -> VaultMetadata? {
        let identity = "\(item.encryptedMetadata.count):\(item.updatedAt.timeIntervalSince1970)"
        if let cached = metadataCache[item.id], cached.identity == identity {
            return cached.metadata
        }
        guard let rootKey = try? VaultCryptoService.ensureRootKey() else { return nil }
        guard let metadata = try? VaultCryptoService.decryptCodable(
            VaultMetadata.self,
            from: item.encryptedMetadata,
            using: rootKey
        ) else {
            metadataCache[item.id] = nil
            return nil
        }
        metadataCache[item.id] = (identity, metadata)
        return metadata
    }

    func thumbnail(for item: VaultItem) -> UIImage? {
        guard let request = try? thumbnailLoadRequest(for: item) else { return nil }
        if let cached = cachedThumbnail(forKey: request.cacheKey) {
            return cached
        }

        do {
            let fileKey = try VaultCryptoService.unwrapFileKey(
                request.encryptedFileKey,
                rootKey: request.rootKey
            )
            let encrypted = try VaultFileStore.read(path: request.encryptedThumbPath)
            let data = try VaultCryptoService.decrypt(encrypted, using: fileKey)
            guard let image = UIImage(data: data) else {
                logger.error("Thumbnail data could not decode for item \(item.id, privacy: .public)")
                return nil
            }
            cacheThumbnail(image, forKey: request.cacheKey)
            return image
        } catch {
            logger.error("Thumbnail load failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func cachedThumbnail(for item: VaultItem) -> UIImage? {
        guard let cacheKey = thumbnailCacheKey(for: item) else { return nil }
        return cachedThumbnail(forKey: cacheKey)
    }

    func loadThumbnail(for item: VaultItem) async -> UIImage? {
        guard let request = try? thumbnailLoadRequest(for: item) else { return nil }
        if let cached = cachedThumbnail(forKey: request.cacheKey) {
            return cached
        }

        let requestedGeneration = mediaCacheGeneration
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let displayImage = await thumbnailDataLoader.image(for: request) else {
            logger.error("Thumbnail data could not decode for item \(item.id, privacy: .public)")
            return nil
        }
        guard !Task.isCancelled, requestedGeneration == mediaCacheGeneration else { return nil }
        cacheThumbnail(displayImage, forKey: request.cacheKey)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        if elapsedMs > 500 {
            logger.debug("Thumbnail loaded asynchronously kind=\(item.kind.rawValue, privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
        }
        return displayImage
    }

    private func thumbnailLoadRequest(for item: VaultItem) throws -> VaultThumbnailLoadRequest? {
        guard let thumbPath = item.encryptedThumbPath, !thumbPath.isEmpty,
              let cacheKey = thumbnailCacheKey(for: item) else {
            return nil
        }
        let rootKey: SymmetricKey
        if let thumbnailRootKey {
            rootKey = thumbnailRootKey
        } else {
            let loadedRootKey = try VaultCryptoService.ensureRootKey()
            thumbnailRootKey = loadedRootKey
            rootKey = loadedRootKey
        }
        return VaultThumbnailLoadRequest(
            cacheKey: cacheKey,
            encryptedThumbPath: thumbPath,
            encryptedFileKey: item.encryptedFileKey,
            rootKey: rootKey
        )
    }

    private func thumbnailCacheKey(for item: VaultItem) -> String? {
        guard let thumbPath = item.encryptedThumbPath, !thumbPath.isEmpty else { return nil }
        return "\(item.id):\(thumbPath):\(item.updatedAt.timeIntervalSince1970)"
    }

    private func cachedThumbnail(forKey cacheKey: String) -> UIImage? {
        thumbnailCache.object(forKey: cacheKey as NSString)
    }

    private func cacheThumbnail(_ image: UIImage, forKey cacheKey: String) {
        let cost: Int
        if let cgImage = image.cgImage {
            cost = cgImage.bytesPerRow * cgImage.height
        } else {
            cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        }
        thumbnailCache.setObject(image, forKey: cacheKey as NSString, cost: max(cost, 1))
    }

    func needsMediaPreviewRepair(_ item: VaultItem) -> Bool {
        VaultCloudAssetDownloadPolicy.needsLocalPreview(item)
            || VaultMediaPreviewRepairPolicy.needsVideoDuration(
                kind: item.kind,
                storedDuration: metadata(for: item)?.mediaDurationSeconds,
                hasLocalOriginal: item.assetState == .local && VaultFileStore.fileExists(path: item.encryptedFilePath)
            )
    }

    func decryptedTemporaryURL(for item: VaultItem) throws -> URL {
        let rootKey = try VaultCryptoService.ensureRootKey()
        let fileKey = try VaultCryptoService.unwrapFileKey(item.encryptedFileKey, rootKey: rootKey)
        let encrypted = try VaultFileStore.read(path: item.encryptedFilePath)
        let data = try VaultCryptoService.decrypt(encrypted, using: fileKey)
        let name = metadata(for: item)?.originalName ?? "\(item.id).bin"
        return try VaultFileStore.temporaryPlainURL(fileName: name, data: data)
    }

    func decryptedTemporaryURL(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws -> URL {
        if item.kind == .link, let urlString = metadata(for: item)?.remoteURL {
            return try VaultFileStore.temporaryPlainURL(
                fileName: "\(item.id).url",
                data: Data(urlString.utf8)
            )
        }

        if !VaultFileStore.fileExists(path: item.encryptedFilePath) || item.assetState == .cloudOnly {
            try await downloadOriginalIfNeeded(for: item, context: context, sync: sync)
        } else {
            markLocalOriginalAccessed(for: item, context: context)
        }
        let rootKey = try VaultCryptoService.ensureRootKey()
        let name = metadata(for: item)?.originalName ?? "\(item.id).bin"
        let request = VaultPreviewFileLoadRequest(
            cacheKey: VaultPreviewFileCachePolicy.cacheKey(
                itemID: item.id,
                encryptedFilePath: item.encryptedFilePath,
                encryptedFileKey: item.encryptedFileKey,
                updatedAt: item.updatedAt
            ),
            fileName: name,
            encryptedFilePath: item.encryptedFilePath,
            encryptedFileKey: item.encryptedFileKey,
            rootKey: rootKey
        )
        return try await previewFileLoader.url(for: request)
    }

    func decryptedLivePhotoResourceURLs(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws -> [URL] {
        let packageURL = try await decryptedTemporaryURL(for: item, context: context, sync: sync)
        let packageData = try Data(contentsOf: packageURL)
        let package = try PropertyListDecoder().decode(LivePhotoPackage.self, from: packageData)
        let stillURL = try VaultFileStore.temporaryPlainURL(fileName: package.stillFilename, data: package.stillData)
        let pairedVideoURL = try VaultFileStore.temporaryPlainURL(fileName: package.pairedVideoFilename, data: package.pairedVideoData)
        return [stillURL, pairedVideoURL]
    }

    func decryptedTemporaryURLs(for items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async -> [URL] {
        var urls: [URL] = []
        for item in items where item.deletedAt == nil {
            if item.kind == .link,
               let urlString = metadata(for: item)?.remoteURL,
               let url = URL(string: urlString) {
                urls.append(url)
                continue
            }

            if let url = try? await decryptedTemporaryURL(for: item, context: context, sync: sync) {
                urls.append(url)
            }
        }
        return urls
    }

    func toggleFavorite(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        item.isFavorite.toggle()
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        try? context.save()
        _ = await sync.syncItem(item)
        try? context.save()
    }

    func rename(_ item: VaultItem, to name: String, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            guard var metadata = metadata(for: item) else { return }
            let existingExtension = metadata.originalExtension?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let submittedExtension = (trimmed as NSString).pathExtension
            let displayName: String
            if submittedExtension.isEmpty, !existingExtension.isEmpty {
                displayName = (trimmed as NSString).appendingPathExtension(existingExtension) ?? trimmed
            } else {
                displayName = trimmed
            }

            metadata.originalName = displayName
            metadata.originalExtension = (displayName as NSString).pathExtension
            item.encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
            try context.save()
            _ = await sync.syncItem(item)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func permanentlyDelete(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        guard await sync.deleteItem(item) else {
            item.syncStatus = .failed
            try? context.save()
            lastError = sync.lastSyncError ?? L.string("iCloud delete failed. Local encrypted data was kept.")
            return
        }

        VaultFileStore.remove(path: item.encryptedFilePath)
        VaultFileStore.remove(path: item.encryptedThumbPath)
        context.delete(item)
        try? context.save()
    }

    func deleteImmediately(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        item.deletedAt = item.deletedAt ?? Date()
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        let encryptedFilePath = item.encryptedFilePath
        let encryptedThumbPath = item.encryptedThumbPath
        try? context.save()
        VaultFileStore.remove(path: item.encryptedFilePath)
        VaultFileStore.remove(path: item.encryptedThumbPath)

        // 删除体验必须先本地生效；iCloud 墓碑记录放到后台同步，避免 CloudKit 慢时卡住界面。
        Task { @MainActor in
            let success = await sync.syncItem(item)
            if !success {
                item.syncStatus = .pending
                item.lastSyncError = sync.lastSyncError
            }
            try? context.save()
            VaultFileStore.remove(path: encryptedFilePath)
            VaultFileStore.remove(path: encryptedThumbPath)
        }
    }

    func deleteImmediately(_ items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess(), !items.isEmpty else { return }
        let deletionTargets = items
            .filter { $0.deletedAt == nil }
            .map { item in
                (item: item, encryptedFilePath: item.encryptedFilePath, encryptedThumbPath: item.encryptedThumbPath)
            }
        guard !deletionTargets.isEmpty else { return }

        let now = Date()
        for target in deletionTargets {
            target.item.deletedAt = now
            target.item.updatedAt = now
            target.item.localRevision += 1
            target.item.syncStatus = .pending
        }
        try? context.save()

        for target in deletionTargets {
            VaultFileStore.remove(path: target.encryptedFilePath)
            VaultFileStore.remove(path: target.encryptedThumbPath)
        }

        // 批量删除只启动一个后台同步任务，避免大量照片删除时同时创建很多 CloudKit 请求。
        Task { @MainActor in
            for target in deletionTargets {
                let success = await sync.syncItem(target.item)
                if !success {
                    target.item.syncStatus = .pending
                    target.item.lastSyncError = sync.lastSyncError
                }
                VaultFileStore.remove(path: target.encryptedFilePath)
                VaultFileStore.remove(path: target.encryptedThumbPath)
            }
            try? context.save()
        }
    }

    func createFolder(named name: String, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let encryptedName = try VaultCryptoService.encryptString(trimmed, using: rootKey)
            let folder = VaultFolder(encryptedName: encryptedName, sortOrder: Int(Date().timeIntervalSince1970))
            context.insert(folder)
            try context.save()
            _ = await sync.syncFolder(folder)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func folderName(_ folder: VaultFolder) -> String {
        guard let rootKey = try? VaultCryptoService.ensureRootKey(),
              let name = try? VaultCryptoService.decryptString(folder.encryptedName, using: rootKey) else {
            return L.string("Untitled Album")
        }
        return name
    }

    func move(_ item: VaultItem, to folder: VaultFolder?, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        item.folderId = folder?.id
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        try? context.save()
        _ = await sync.syncItem(item)
        try? context.save()
    }

    func ensureInnerVaultFolder(context: ModelContext, sync: CloudKitSyncService) async -> VaultFolder? {
        guard requireWriteAccess() else { return nil }
        do {
            let innerVaultFolderId = Self.innerVaultFolderId
            let descriptor = FetchDescriptor<VaultFolder>(
                predicate: #Predicate<VaultFolder> { folder in
                    folder.id == innerVaultFolderId
                }
            )
            if let existing = try context.fetch(descriptor).first {
                if existing.deletedAt != nil {
                    existing.deletedAt = nil
                    existing.updatedAt = Date()
                    existing.localRevision += 1
                    existing.syncStatus = .pending
                    try context.save()
                    _ = await sync.syncFolder(existing)
                    try? context.save()
                }
                return existing
            }

            let rootKey = try VaultCryptoService.ensureRootKey()
            let encryptedName = try VaultCryptoService.encryptString("墨层", using: rootKey)
            let folder = VaultFolder(
                id: Self.innerVaultFolderId,
                encryptedName: encryptedName,
                sortOrder: Int.max
            )
            context.insert(folder)
            try context.save()
            _ = await sync.syncFolder(folder)
            try? context.save()
            return folder
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func moveToInnerVault(_ items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        guard await ensureInnerVaultFolder(context: context, sync: sync) != nil else { return false }
        return await move(items, toFolderId: Self.innerVaultFolderId, context: context, sync: sync)
    }

    @discardableResult
    func moveOutOfInnerVault(_ items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        await move(items, toFolderId: nil, context: context, sync: sync)
    }

    @discardableResult
    func move(_ items: [VaultItem], toFolderId folderId: String?, context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        guard requireWriteAccess(), !items.isEmpty else { return false }
        var didMove = false
        for item in items where item.deletedAt == nil {
            item.folderId = folderId
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
            didMove = true
        }
        guard didMove else { return false }
        try? context.save()
        for item in items where item.deletedAt == nil {
            _ = await sync.syncItem(item)
        }
        try? context.save()
        return true
    }

    func renameFolder(_ folder: VaultFolder, to name: String, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            folder.encryptedName = try VaultCryptoService.encryptString(trimmed, using: rootKey)
            folder.updatedAt = Date()
            folder.localRevision += 1
            folder.syncStatus = .pending
            try context.save()
            _ = await sync.syncFolder(folder)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteFolder(_ folder: VaultFolder, items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        for item in items where item.folderId == folder.id {
            item.folderId = nil
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
        }
        folder.deletedAt = Date()
        folder.updatedAt = Date()
        folder.localRevision += 1
        folder.syncStatus = .pending
        try? context.save()

        _ = await sync.syncFolder(folder)
        for item in items where item.syncStatus == .pending {
            _ = await sync.syncItem(item)
        }
        try? context.save()
    }

    func decoyNotePayload(for note: DecoyNoteRecord) -> DecoyNotePayload? {
        guard let rootKey = try? VaultCryptoService.ensureRootKey() else { return nil }
        return try? VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: note.encryptedPayload, using: rootKey)
    }

    func createDecoyNote(
        id: String = UUID().uuidString,
        payload: DecoyNotePayload,
        isPinned: Bool = false,
        sortOrder: Double = Date().timeIntervalSince1970,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let encryptedPayload = try VaultCryptoService.encryptCodable(payload, using: rootKey)
            let note = DecoyNoteRecord(id: id, encryptedPayload: encryptedPayload, isPinned: isPinned, sortOrder: sortOrder)
            context.insert(note)
            try context.save()
            _ = await sync.syncDecoyNote(note)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateDecoyNote(
        _ note: DecoyNoteRecord,
        payload: DecoyNotePayload,
        isPinned: Bool,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            note.encryptedPayload = try VaultCryptoService.encryptCodable(payload, using: rootKey)
            note.isPinned = isPinned
            note.updatedAt = Date()
            note.localRevision += 1
            note.syncStatus = .pending
            note.lastSyncError = nil
            try context.save()
            _ = await sync.syncDecoyNote(note)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleDecoyTodo(
        _ note: DecoyNoteRecord,
        todoId: String,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        guard var payload = decoyNotePayload(for: note),
              let index = payload.todos.firstIndex(where: { $0.id == todoId }) else {
            return
        }
        payload.todos[index].done.toggle()
        await updateDecoyNote(note, payload: payload, isPinned: note.isPinned, context: context, sync: sync)
    }

    func toggleDecoyPin(_ note: DecoyNoteRecord, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        guard let payload = decoyNotePayload(for: note) else { return }
        await updateDecoyNote(note, payload: payload, isPinned: !note.isPinned, context: context, sync: sync)
    }

    func deleteDecoyNote(_ note: DecoyNoteRecord, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        note.deletedAt = Date()
        note.updatedAt = Date()
        note.localRevision += 1
        note.syncStatus = .pending
        note.lastSyncError = nil
        try? context.save()
        _ = await sync.syncDecoyNote(note)
        try? context.save()
    }

    func reorderDecoyNotes(_ notes: [DecoyNoteRecord], from source: IndexSet, to destination: Int, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        var reordered = notes
        reordered.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        for (index, note) in reordered.enumerated() {
            note.sortOrder = Double(reordered.count - index)
            note.updatedAt = now
            note.localRevision += 1
            note.syncStatus = .pending
        }
        try? context.save()
        for note in reordered {
            _ = await sync.syncDecoyNote(note)
        }
        try? context.save()
    }

    func ensureDefaultDecoyNotes(_ defaults: [(id: String, payload: DecoyNotePayload, isPinned: Bool)], context: ModelContext, sync: CloudKitSyncService) async {
        guard allowsVaultWrites else { return }
        do {
            var descriptor = FetchDescriptor<DecoyNoteRecord>()
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).isEmpty else { return }

            let baseSort = Date().timeIntervalSince1970
            for (index, item) in defaults.enumerated() {
                await createDecoyNote(
                    id: item.id,
                    payload: item.payload,
                    isPinned: item.isPinned,
                    sortOrder: baseSort - Double(index),
                    context: context,
                    sync: sync
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pullCloudDecoyNotes(context: ModelContext, sync: CloudKitSyncService) async {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let remoteRecords = await sync.fetchRemoteDecoyNotes()
            let existing = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
            var notesById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for record in remoteRecords {
                guard let noteId = record["noteId"] as? String else { continue }
                let encryptedPayload = record["encryptedPayload"] as? Data ?? Data()
                guard (try? VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: encryptedPayload, using: rootKey)) != nil else {
                    continue
                }
                let remoteUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
                let remoteRevision = record["localRevision"] as? Int ?? 1

                if let note = notesById[noteId] {
                    guard VaultRemoteMergePolicy.shouldApplyRemote(
                        remoteUpdatedAt: remoteUpdatedAt,
                        remoteRevision: remoteRevision,
                        localUpdatedAt: note.updatedAt,
                        localRevision: note.localRevision,
                        localSyncStatus: note.syncStatus
                    ) else { continue }
                    note.encryptedPayload = encryptedPayload
                    note.isPinned = (record["isPinned"] as? Int ?? (note.isPinned ? 1 : 0)) == 1
                    note.sortOrder = record["sortOrder"] as? Double ?? note.sortOrder
                    note.createdAt = record["createdAt"] as? Date ?? note.createdAt
                    note.updatedAt = remoteUpdatedAt
                    note.deletedAt = record["deletedAt"] as? Date
                    note.localRevision = remoteRevision
                    note.cloudRecordName = record.recordID.recordName
                    note.syncStatus = .synced
                    note.lastSyncError = nil
                } else {
                    let note = DecoyNoteRecord(
                        id: noteId,
                        encryptedPayload: encryptedPayload,
                        isPinned: (record["isPinned"] as? Int ?? 0) == 1,
                        sortOrder: record["sortOrder"] as? Double ?? remoteUpdatedAt.timeIntervalSince1970
                    )
                    note.createdAt = record["createdAt"] as? Date ?? Date()
                    note.updatedAt = remoteUpdatedAt
                    note.deletedAt = record["deletedAt"] as? Date
                    note.localRevision = remoteRevision
                    note.cloudRecordName = record.recordID.recordName
                    note.syncStatus = .synced
                    note.lastSyncError = nil
                    context.insert(note)
                    notesById[noteId] = note
                }
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncPendingDecoyNotes(context: ModelContext, sync: CloudKitSyncService) async {
        guard allowsVaultWrites else { return }
        do {
            let notes = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
            for note in notes where note.syncStatus != .synced {
                _ = await sync.syncDecoyNote(note)
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncPendingChanges(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async {
        guard allowsCloudSync, allowsVaultWrites else { return }
        await syncChanges(context: context, sync: sync, forceItems: false)
    }

    @discardableResult
    func syncCloudToLocal(
        context: ModelContext,
        sync: CloudKitSyncService,
        allowsCloudSync: Bool = true,
        allowsCloudWrite: Bool? = nil,
        purpose: VaultCloudToLocalSyncPurpose = .routineSync,
        downloadsOriginals: Bool? = nil
    ) async -> CloudAssetDownloadSummary {
        guard allowsCloudSync else { return CloudAssetDownloadSummary() }
        let canWriteCloud = allowsCloudWrite ?? allowsCloudSync
        let shouldDownloadOriginals = VaultCloudToLocalSyncPolicy.downloadsOriginals(
            purpose: purpose,
            explicitOverride: downloadsOriginals
        )

        if case .routineSync = purpose, !shouldDownloadOriginals {
            if let task = routineCloudToLocalSyncTasks[canWriteCloud] {
                sync.appendLog("Coalesced overlapping routine iCloud sync")
                return await task.value
            }
            let task = Task { @MainActor [weak self] in
                guard let self else { return CloudAssetDownloadSummary() }
                return await self.performCloudToLocalSync(
                    context: context,
                    sync: sync,
                    allowsCloudSync: allowsCloudSync,
                    canWriteCloud: canWriteCloud,
                    shouldDownloadOriginals: false
                )
            }
            routineCloudToLocalSyncTasks[canWriteCloud] = task
            let summary = await task.value
            routineCloudToLocalSyncTasks[canWriteCloud] = nil
            return summary
        }

        return await performCloudToLocalSync(
            context: context,
            sync: sync,
            allowsCloudSync: allowsCloudSync,
            canWriteCloud: canWriteCloud,
            shouldDownloadOriginals: shouldDownloadOriginals
        )
    }

    private func performCloudToLocalSync(
        context: ModelContext,
        sync: CloudKitSyncService,
        allowsCloudSync: Bool,
        canWriteCloud: Bool,
        shouldDownloadOriginals: Bool
    ) async -> CloudAssetDownloadSummary {
        let indexSummary = await pullCloudIndexSummary(context: context, sync: sync, allowsCloudSync: allowsCloudSync)
        let indexedCount = indexSummary.indexed
        await pullCloudDecoyNotes(context: context, sync: sync)
        await syncPendingChanges(context: context, sync: sync, allowsCloudSync: canWriteCloud)

        guard shouldDownloadOriginals else {
            let summary = CloudAssetDownloadSummary(indexedItems: indexedCount)
            restoreStatusMessage = summary.displayText
            return summary
        }

        return await downloadMissingCloudAssets(context: context, sync: sync, indexedItems: indexedCount)
    }

    @discardableResult
    func backupAllFilesToCloud(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async -> CloudSyncRunSummary? {
        guard allowsCloudSync, allowsVaultWrites else {
            lastError = L.string("Renew Pro to use encrypted iCloud backup and multi-device sync.")
            sync.clearLogs()
            sync.beginSyncRun(itemCount: 0, folderCount: 0, decoyNoteCount: 0, manifestCount: 0)
            sync.recordItemSync(success: false, failure: lastError)
            sync.finishSyncRun()
            return sync.lastRunSummary
        }
        await syncChanges(context: context, sync: sync, forceItems: true, manualRun: true)
        return sync.lastRunSummary
    }

    @discardableResult
    func pullCloudIndex(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async -> Int {
        await pullCloudIndexSummary(context: context, sync: sync, allowsCloudSync: allowsCloudSync).indexed
    }

    private func pullCloudIndexSummary(
        context: ModelContext,
        sync: CloudKitSyncService,
        allowsCloudSync: Bool
    ) async -> VaultCloudIndexPullSummary {
        guard allowsCloudSync else { return VaultCloudIndexPullSummary() }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            await pullCloudFolders(context: context, sync: sync)
            let remoteRecords = await sync.fetchRemoteItemsForIndex()
            let existingItems = try context.fetch(FetchDescriptor<VaultItem>())
            var itemsById = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            var summary = VaultCloudIndexPullSummary(fetched: remoteRecords.count)

            for record in remoteRecords {
                guard let itemId = record["itemId"] as? String else {
                    summary.missingIdentity += 1
                    continue
                }

                let kind = VaultItemKind(rawValue: record["type"] as? String ?? "") ?? .other
                let encryptedMetadata = record["encryptedMetadata"] as? Data ?? Data()
                switch VaultCloudMetadataInspector.classify(encryptedMetadata, using: rootKey) {
                case .readable:
                    summary.indexed += 1
                case .incompatiblePayload:
                    summary.incompatiblePayload += 1
                    continue
                case .wrongRootKey:
                    summary.wrongRootKey += 1
                    continue
                }
                let encryptedFileKey = record["encryptedFileKey"] as? Data ?? Data()
                let byteSize = record["byteSize"] as? Int64 ?? 0
                let folderId = record["folderId"] as? String
                let remoteDeletedAt = record["deletedAt"] as? Date
                let remoteUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
                let remoteRevision = record["localRevision"] as? Int ?? 1

                if let existing = itemsById[itemId] {
                    guard VaultRemoteMergePolicy.shouldApplyRemote(
                        remoteUpdatedAt: remoteUpdatedAt,
                        remoteRevision: remoteRevision,
                        localUpdatedAt: existing.updatedAt,
                        localRevision: existing.localRevision,
                        localSyncStatus: existing.syncStatus
                    ) else { continue }
                    existing.kindRawValue = kind.rawValue
                    existing.encryptedMetadata = encryptedMetadata
                    existing.encryptedFileKey = encryptedFileKey
                    existing.byteSize = byteSize
                    existing.folderId = folderId
                    existing.isFavorite = (record["favorite"] as? Int ?? (existing.isFavorite ? 1 : 0)) == 1
                    existing.deletedAt = remoteDeletedAt
                    existing.localRevision = remoteRevision
                    existing.importFingerprint = record["importFingerprint"] as? String
                    existing.cloudRecordName = record.recordID.recordName
                    existing.syncStatus = .synced
                    existing.lastSyncError = nil
                    existing.updatedAt = remoteUpdatedAt
                    if !VaultFileStore.fileExists(path: existing.encryptedFilePath), kind != .link {
                        existing.assetState = .cloudOnly
                    }
                } else {
                    let item = VaultItem(
                        id: itemId,
                        kind: kind,
                        encryptedFilePath: "",
                        encryptedThumbPath: nil,
                        encryptedMetadata: encryptedMetadata,
                        encryptedFileKey: encryptedFileKey,
                        byteSize: byteSize,
                        folderId: folderId,
                        assetState: kind == .link ? .local : .cloudOnly,
                        cloudRecordName: record.recordID.recordName,
                        importFingerprint: record["importFingerprint"] as? String
                    )
                    item.createdAt = record["createdAt"] as? Date ?? Date()
                    item.updatedAt = remoteUpdatedAt
                    item.deletedAt = remoteDeletedAt
                    item.isFavorite = (record["favorite"] as? Int ?? 0) == 1
                    item.localRevision = remoteRevision
                    item.syncStatus = .synced
                    item.lastSyncError = nil
                    context.insert(item)
                    itemsById[itemId] = item
                }
            }
            try context.save()
            cloudIndexRevision &+= 1
            sync.appendLog(
                "Cloud index merge fetched=\(summary.fetched) indexed=\(summary.indexed) missingIdentity=\(summary.missingIdentity) incompatiblePayload=\(summary.incompatiblePayload) wrongRootKey=\(summary.wrongRootKey)"
            )
            if VaultRecoverySelectionPolicy.shouldRequestRecovery(
                readableItemCount: summary.indexed,
                wrongRootKeyCount: summary.wrongRootKey
            ) {
                requiresVaultRecovery = true
                let manifestCandidates = await sync.fetchRemoteManifestCandidates()
                let currentKeyCandidates = manifestCandidates.filter { record in
                    guard let encryptedName = record["encryptedVaultName"] as? Data else { return false }
                    return (try? VaultCryptoService.decryptString(encryptedName, using: rootKey)) != nil
                }
                let recoverableCandidates = manifestCandidates.filter { record in
                    guard let package = record["encryptedRootKeyPackage"] as? Data else { return false }
                    return VaultCryptoService.canRestoreRootKey(from: package)
                }
                sync.appendLog(
                    "Cloud manifest recovery candidates total=\(manifestCandidates.count) currentKey=\(currentKeyCandidates.count) recoveryKey=\(recoverableCandidates.count)"
                )
                let message = L.format(
                    "%d iCloud item(s) belong to a vault key that is not available on this device. Restore the original vault with its recovery key.",
                    summary.wrongRootKey
                )
                lastError = message
                sync.lastSyncError = message
            } else if summary.wrongRootKey > 0 {
                requiresVaultRecovery = false
                sync.appendLog(
                    "Ignored minority records from another vault key readable=\(summary.indexed) wrongRootKey=\(summary.wrongRootKey)"
                )
                lastError = nil
                sync.lastSyncError = nil
            } else if summary.incompatiblePayload > 0 {
                requiresVaultRecovery = false
                let message = L.format(
                    "%d iCloud item(s) use an unsupported metadata format. Update the app before trying again.",
                    summary.incompatiblePayload
                )
                lastError = message
                sync.lastSyncError = message
            } else if summary.skipped == 0 {
                requiresVaultRecovery = false
                lastError = nil
                sync.lastSyncError = nil
            }
            return summary
        } catch {
            lastError = error.localizedDescription
            sync.appendLog("Cloud index merge failed: \(error.localizedDescription)")
            return VaultCloudIndexPullSummary()
        }
    }

    func downloadOriginalIfNeeded(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws {
        guard item.kind != .link else { return }
        if VaultFileStore.fileExists(path: item.encryptedFilePath), item.assetState == .local {
            return
        }

        if let existingTask = originalDownloadTasks[item.id] {
            try await existingTask.value
            return
        }

        let task: Task<Void, Error> = Task { @MainActor in
            try await self.performOriginalDownload(for: item, context: context, sync: sync)
        }
        originalDownloadTasks[item.id] = task
        defer { originalDownloadTasks[item.id] = nil }
        try await task.value
    }

    private func performOriginalDownload(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws {
        let assets = await sync.downloadAssets(for: item)
        guard let fileURL = assets.fileURL else {
            throw VaultCryptoService.CryptoError.missingRootKey
        }
        item.encryptedFilePath = try VaultFileStore.copyEncryptedObject(from: fileURL, itemId: item.id)
        if let thumbURL = assets.thumbURL {
            item.encryptedThumbPath = try? VaultFileStore.copyEncryptedThumb(from: thumbURL, itemId: item.id)
        }
        item.assetState = .local
        item.downloadedAt = Date()
        item.lastDownloadError = nil
        if VaultCloudAssetDownloadPolicy.needsLocalPreview(item),
           let encryptedThumbPath = await makeEncryptedThumbnail(for: item) {
            item.encryptedThumbPath = encryptedThumbPath
        }
        try context.save()
    }

    @discardableResult
    func downloadThumbnailIfAvailable(for item: VaultItem, sync: CloudKitSyncService) async -> Bool {
        guard item.deletedAt == nil, item.kind.isVisualMedia else { return false }
        guard VaultCloudAssetDownloadPolicy.needsLocalPreview(item) else { return true }
        if let existingTask = thumbnailDownloadTasks[item.id] {
            return await existingTask.value
        }

        let task = Task { @MainActor in
            await self.performThumbnailDownload(for: item, sync: sync)
        }
        thumbnailDownloadTasks[item.id] = task
        let result = await task.value
        thumbnailDownloadTasks[item.id] = nil
        return result
    }

    private func performThumbnailDownload(for item: VaultItem, sync: CloudKitSyncService) async -> Bool {
        guard let thumbURL = await sync.downloadThumbnail(for: item) else { return false }
        do {
            item.encryptedThumbPath = try VaultFileStore.copyEncryptedThumb(from: thumbURL, itemId: item.id)
            item.lastDownloadError = nil
            return true
        } catch {
            item.lastDownloadError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func ensureMediaPreviews(
        for items: [VaultItem],
        context: ModelContext,
        sync: CloudKitSyncService,
        syncAfterRepair: Bool = false
    ) async -> Bool {
        let candidates = items.filter(needsMediaPreviewRepair)
        guard !candidates.isEmpty else { return false }

        var repairedCount = 0
        var generatedPreviewNeedsSync = false
        await withTaskGroup(of: (Bool, Bool).self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard !Task.isCancelled, nextIndex < candidates.count else { return }
                let item = candidates[nextIndex]
                nextIndex += 1
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return (false, false) }
                    return await self.repairMediaPreview(for: item, context: context, sync: sync, syncAfterRepair: syncAfterRepair)
                }
            }
            for _ in 0..<4 {
                enqueueNext()
            }
            for await (repairedItem, needsSync) in group {
                if repairedItem {
                    repairedCount += 1
                }
                generatedPreviewNeedsSync = generatedPreviewNeedsSync || needsSync
                if Task.isCancelled {
                    group.cancelAll()
                } else {
                    enqueueNext()
                }
            }
        }
        if repairedCount > 0 {
            logger.info("Repaired media previews for \(repairedCount, privacy: .public) vault items")
        }
        return generatedPreviewNeedsSync
    }

    private func repairMediaPreview(
        for item: VaultItem,
        context: ModelContext,
        sync: CloudKitSyncService,
        syncAfterRepair: Bool
    ) async -> (Bool, Bool) {
        var repairedItem = false
        var generatedLocalChange = false

        if VaultCloudAssetDownloadPolicy.needsLocalPreview(item) {
            if await downloadThumbnailIfAvailable(for: item, sync: sync) {
                repairedItem = true
            } else if !Task.isCancelled, VaultFileStore.fileExists(path: item.encryptedFilePath),
                      item.assetState == .local,
                      let encryptedThumbPath = await makeEncryptedThumbnail(for: item) {
                item.encryptedThumbPath = encryptedThumbPath
                repairedItem = true
                generatedLocalChange = true
            }
        }

        if !Task.isCancelled, VaultMediaPreviewRepairPolicy.needsVideoDuration(
            kind: item.kind,
            storedDuration: metadata(for: item)?.mediaDurationSeconds,
            hasLocalOriginal: item.assetState == .local && VaultFileStore.fileExists(path: item.encryptedFilePath)
        ), await repairMissingVideoDuration(for: item) {
            repairedItem = true
            generatedLocalChange = true
        }

        if generatedLocalChange {
            item.updatedAt = Date()
            if syncAfterRepair {
                item.localRevision += 1
                item.syncStatus = .pending
            }
            if item.syncStatus == .synced {
                releaseLocalOriginalIfBackedUp(for: item)
            }
        }
        if repairedItem {
            // Publish each completed thumbnail instead of waiting for the slowest download.
            try? context.save()
            objectWillChange.send()
        }
        return (repairedItem, generatedLocalChange && syncAfterRepair)
    }

    private func repairMissingVideoDuration(for item: VaultItem) async -> Bool {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let fileKey = try VaultCryptoService.unwrapFileKey(item.encryptedFileKey, rootKey: rootKey)
            guard var metadata = try? VaultCryptoService.decryptCodable(
                VaultMetadata.self,
                from: item.encryptedMetadata,
                using: rootKey
            ), metadata.mediaDurationSeconds == nil else {
                return false
            }
            let encryptedFilePath = item.encryptedFilePath
            let kind = item.kind
            let preferredExtension = metadata.originalExtension
            let duration = try await Task.detached(priority: .utility) {
                let encryptedFile = try VaultFileStore.read(path: encryptedFilePath)
                let data = try VaultCryptoService.decrypt(encryptedFile, using: fileKey)
                return await VaultImportArtifactBuilder.mediaDurationSeconds(
                    from: data,
                    kind: kind,
                    preferredExtension: preferredExtension
                )
            }.value
            guard let duration else {
                return false
            }
            metadata.mediaDurationSeconds = duration
            item.encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
            return true
        } catch {
            logger.error("Video duration repair failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    func downloadAllCloudAssets(context: ModelContext, sync: CloudKitSyncService) async -> CloudAssetDownloadSummary {
        let indexedItems = await pullCloudIndex(context: context, sync: sync)
        return await downloadMissingCloudAssets(context: context, sync: sync, indexedItems: indexedItems)
    }

    @discardableResult
    private func downloadMissingCloudAssets(
        context: ModelContext,
        sync: CloudKitSyncService,
        indexedItems: Int
    ) async -> CloudAssetDownloadSummary {
        var summary = CloudAssetDownloadSummary(indexedItems: indexedItems)
        do {
            let descriptor = FetchDescriptor<VaultItem>()
            let items = try context.fetch(descriptor)
            let candidates = items.filter { VaultCloudAssetDownloadPolicy.shouldDownload($0) }
            summary.total = candidates.count
            sync.appendLog("Starting full iCloud asset download count=\(candidates.count)")

            for item in candidates {
                do {
                    try await downloadOriginalIfNeeded(for: item, context: context, sync: sync)
                    summary.succeeded += 1
                } catch {
                    item.assetState = .failed
                    item.lastDownloadError = error.localizedDescription
                    summary.failed += 1
                    summary.failureMessages.append(error.localizedDescription)
                    sync.appendLog("Full asset download failed id=\(item.id) error=\(error.localizedDescription)")
                }
            }

            try context.save()
            sync.appendLog("Finished full iCloud asset download success=\(summary.succeeded) failed=\(summary.failed) total=\(summary.total)")
        } catch {
            summary.failed += 1
            summary.failureMessages.append(error.localizedDescription)
            lastError = error.localizedDescription
            sync.appendLog("Full iCloud asset download failed: \(error.localizedDescription)")
        }

        restoreStatusMessage = summary.displayText
        return summary
    }

    @discardableResult
    func releaseLocalOriginal(for item: VaultItem, context: ModelContext) -> Bool {
        let released = releaseLocalOriginalIfBackedUp(for: item, trigger: .manual)
        if released {
            try? context.save()
            objectWillChange.send()
        }
        return released
    }

    @discardableResult
    func releaseLocalOriginals(for items: [VaultItem], context: ModelContext) -> Int {
        let count = items.reduce(0) { partial, item in
            partial + (releaseLocalOriginalIfBackedUp(for: item, trigger: .manual) ? 1 : 0)
        }
        if count > 0 {
            try? context.save()
            objectWillChange.send()
        }
        return count
    }

    @discardableResult
    func offloadOriginalsIfNeeded(context: ModelContext) -> Int {
        guard VaultOptimizedStoragePolicy.isEnabledByDefault else { return 0 }
        let objectBytes = VaultFileStore.encryptedObjectBytes()
        let availableBytes = VaultFileStore.availableCapacityForImportantUsage()
        guard objectBytes > VaultOptimizedStoragePolicy.maxLocalOriginalCacheBytes
                || availableBytes < VaultOptimizedStoragePolicy.lowDiskFreeBytes else {
            return 0
        }

        let items = (try? context.fetch(FetchDescriptor<VaultItem>())) ?? []
        let candidates = items
            .filter { item in
                item.deletedAt == nil
                    && item.kind != .link
                    && item.syncStatus == .synced
                    && item.assetState == .local
                    && VaultFileStore.fileExists(path: item.encryptedFilePath)
            }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite {
                    return !lhs.isFavorite
                }
                let lhsLarge = lhs.byteSize >= VaultOptimizedStoragePolicy.immediateReleaseByteThreshold
                let rhsLarge = rhs.byteSize >= VaultOptimizedStoragePolicy.immediateReleaseByteThreshold
                if lhsLarge != rhsLarge {
                    return lhsLarge
                }
                let lhsDate = lhs.downloadedAt ?? VaultFileStore.fileModifiedAt(path: lhs.encryptedFilePath) ?? lhs.updatedAt
                let rhsDate = rhs.downloadedAt ?? VaultFileStore.fileModifiedAt(path: rhs.encryptedFilePath) ?? rhs.updatedAt
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.byteSize > rhs.byteSize
            }

        var released = 0
        var remainingBytes = objectBytes
        let targetBytes = objectBytes > VaultOptimizedStoragePolicy.maxLocalOriginalCacheBytes
            ? VaultOptimizedStoragePolicy.targetLocalOriginalCacheBytes
            : VaultOptimizedStoragePolicy.maxLocalOriginalCacheBytes
        for item in candidates {
            guard remainingBytes > targetBytes
                    || VaultFileStore.availableCapacityForImportantUsage() < VaultOptimizedStoragePolicy.lowDiskFreeBytes else {
                break
            }
            let size = VaultFileStore.fileSize(path: item.encryptedFilePath)
            if releaseLocalOriginalIfBackedUp(for: item, trigger: .cachePressure) {
                remainingBytes -= size
                released += 1
            }
        }

        if released > 0 {
            try? context.save()
            objectWillChange.send()
        }
        return released
    }

    @discardableResult
    private func releaseLocalOriginalIfBackedUp(
        for item: VaultItem,
        trigger: VaultOriginalReleaseTrigger = .successfulSync
    ) -> Bool {
        guard !PhotoTransferCoordinator.shared.pinnedVaultIDs.contains(item.id),
              VaultOptimizedStoragePolicy.isEnabledByDefault,
              item.deletedAt == nil,
              item.kind != .link,
              item.syncStatus == .synced,
              item.assetState == .local,
              VaultFileStore.fileExists(path: item.encryptedFilePath) else {
            return false
        }

        if trigger == .successfulSync,
           !VaultOptimizedStoragePolicy.shouldReleaseAfterSuccessfulSync(item) {
            return false
        }

        VaultFileStore.remove(path: item.encryptedFilePath)
        item.assetState = .cloudOnly
        item.downloadedAt = nil
        item.lastDownloadError = nil
        return true
    }

    private func markLocalOriginalAccessed(for item: VaultItem, context: ModelContext) {
        guard item.deletedAt == nil,
              item.kind != .link,
              item.assetState == .local,
              VaultFileStore.fileExists(path: item.encryptedFilePath) else {
            return
        }

        let now = Date()
        if let downloadedAt = item.downloadedAt,
           now.timeIntervalSince(downloadedAt) < VaultOptimizedStoragePolicy.accessTimestampUpdateInterval {
            return
        }
        item.downloadedAt = now
        try? context.save()
    }

    private func repairStoredFileReferences(context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        var repairedCount = 0
        for item in items {
            let normalizedFilePath = VaultFileStore.normalizedStoredPath(item.encryptedFilePath) ?? item.encryptedFilePath
            if normalizedFilePath != item.encryptedFilePath {
                item.encryptedFilePath = normalizedFilePath
                repairedCount += 1
            }

            let normalizedThumbPath = VaultFileStore.normalizedStoredPath(item.encryptedThumbPath)
            if normalizedThumbPath != item.encryptedThumbPath {
                item.encryptedThumbPath = normalizedThumbPath
                repairedCount += 1
            }
        }

        if repairedCount > 0 {
            logger.info("Repaired \(repairedCount, privacy: .public) persisted vault file references")
            try context.save()
        }
    }

    private func repairMissingVideoThumbnails(context: ModelContext) async throws {
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        var repairedCount = 0

        for item in items where shouldRepairVideoThumbnail(item) {
            guard let encryptedThumbPath = await makeEncryptedVideoThumbnail(for: item) else {
                continue
            }
            item.encryptedThumbPath = encryptedThumbPath
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
            repairedCount += 1
        }

        if repairedCount > 0 {
            logger.info("Generated missing video thumbnails for \(repairedCount, privacy: .public) vault items")
            try context.save()
        }
    }

    private func shouldRepairVideoThumbnail(_ item: VaultItem) -> Bool {
        guard item.deletedAt == nil,
              item.kind == .video,
              !item.encryptedFilePath.isEmpty,
              VaultFileStore.fileExists(path: item.encryptedFilePath) else {
            return false
        }

        guard let thumbPath = item.encryptedThumbPath,
              !thumbPath.isEmpty else {
            return true
        }

        return !VaultFileStore.fileExists(path: thumbPath)
    }

    private func makeEncryptedVideoThumbnail(for item: VaultItem) async -> String? {
        await makeEncryptedThumbnail(for: item)
    }

    private func makeEncryptedThumbnail(for item: VaultItem) async -> String? {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let fileKey = try VaultCryptoService.unwrapFileKey(item.encryptedFileKey, rootKey: rootKey)
            let encryptedFile = try VaultFileStore.read(path: item.encryptedFilePath)
            let data = try VaultCryptoService.decrypt(encryptedFile, using: fileKey)
            let metadata = try? VaultCryptoService.decryptCodable(
                VaultMetadata.self,
                from: item.encryptedMetadata,
                using: rootKey
            )
            guard let thumbData = await makeThumbnailData(
                from: data,
                kind: item.kind,
                originalName: metadata?.originalName ?? "",
                mimeType: metadata?.mimeType ?? ""
            ) else {
                return nil
            }

            let encryptedThumb = try VaultCryptoService.encrypt(thumbData, using: fileKey)
            return try VaultFileStore.writeEncryptedThumb(encryptedThumb, itemId: item.id)
        } catch {
            logger.error("Thumbnail repair failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func syncChanges(context: ModelContext, sync: CloudKitSyncService, forceItems: Bool, manualRun: Bool = false) async {
        do {
            let manifests = try context.fetch(FetchDescriptor<VaultManifest>())
            let folders = try context.fetch(FetchDescriptor<VaultFolder>())
            let decoyNotes = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
            let items = try context.fetch(FetchDescriptor<VaultItem>())

            let manifestsToSync = manifests.filter { forceItems || $0.syncStatus != .synced || !VaultCryptoService.canRestoreRootKey(from: $0.encryptedRootKeyPackage) }
            let foldersToSync = folders.filter { forceItems || $0.syncStatus != .synced }
            let decoyNotesToSync = decoyNotes.filter { forceItems || $0.syncStatus != .synced }
            let itemsToSync = items.filter { forceItems || $0.syncStatus != .synced }

            if manualRun {
                sync.clearLogs()
                sync.beginSyncRun(
                    itemCount: itemsToSync.count,
                    folderCount: foldersToSync.count,
                    decoyNoteCount: decoyNotesToSync.count,
                    manifestCount: manifestsToSync.count
                )

                guard await sync.runWritableProbe() else {
                    sync.recordItemSync(success: false, failure: sync.lastSyncError)
                    sync.finishSyncRun()
                    return
                }
            }

            for manifest in manifests {
                if !VaultCryptoService.canRestoreRootKey(from: manifest.encryptedRootKeyPackage) {
                    manifest.encryptedRootKeyPackage = try VaultCryptoService.makeRootKeyPackage()
                    manifest.updatedAt = Date()
                    manifest.syncStatus = .pending
                }
                guard forceItems || manifest.syncStatus != .synced else { continue }
                let success = await sync.syncManifest(manifest)
                if manualRun {
                    sync.recordManifestSync(success: success, failure: success ? nil : sync.lastSyncError)
                }
            }

            for folder in foldersToSync {
                let success = await sync.syncFolder(folder)
                if manualRun {
                    sync.recordFolderSync(success: success, failure: success ? nil : sync.lastSyncError)
                }
            }

            for note in decoyNotesToSync {
                let success = await sync.syncDecoyNote(note)
                if manualRun {
                    sync.recordDecoyNoteSync(success: success, failure: success ? nil : note.lastSyncError ?? sync.lastSyncError)
                }
            }

            for item in itemsToSync {
                if PhotoTransferCoordinator.shared.isRunning && PhotoTransferCoordinator.shared.pinnedVaultIDs.contains(item.id) { continue }
                let success = await sync.syncItem(item)
                if success {
                    releaseLocalOriginalIfBackedUp(for: item)
                }
                if manualRun {
                    sync.recordItemSync(success: success, failure: success ? nil : item.lastSyncError ?? sync.lastSyncError)
                }
            }
            _ = offloadOriginalsIfNeeded(context: context)
            try context.save()
            if manualRun {
                sync.finishSyncRun()
            }
        } catch {
            lastError = error.localizedDescription
            if manualRun {
                sync.recordItemSync(success: false, failure: lastError)
                sync.finishSyncRun()
            }
        }
    }

    private func restoreRemoteManifestUsingAvailableKey(_ record: CKRecord, context: ModelContext) throws -> Bool {
        let package = record["encryptedRootKeyPackage"] as? Data ?? Data()
        if !VaultCryptoService.hasRootKey() {
            _ = try? VaultCryptoService.restoreRootKeyFromICloudKeychain()
        }
        let encryptedVaultName = record["encryptedVaultName"] as? Data ?? Data()
        let rootKey = VaultCryptoService.hasRootKey() ? try? VaultCryptoService.ensureRootKey() : nil
        let canOpenWithLocalRootKey = rootKey.flatMap { try? VaultCryptoService.decryptString(encryptedVaultName, using: $0) } != nil
        let canRestoreFromPackage = VaultCryptoService.canRestoreRootKey(from: package)
        guard canOpenWithLocalRootKey || canRestoreFromPackage else {
            return false
        }

        if VaultRemoteRootKeyPolicy.shouldRestorePackagedKey(
            localKeyOpensManifest: canOpenWithLocalRootKey,
            recoveryKeyOpensPackage: canRestoreFromPackage
        ) {
            let restoredKey = try VaultCryptoService.restoreRootKey(
                from: package,
                recoveryKey: VaultCryptoService.currentRecoveryKey()
            )
            _ = try VaultCryptoService.decryptString(encryptedVaultName, using: restoredKey)
        }

        let manifest = makeManifest(from: record)
        context.insert(manifest)
        try context.save()
        return true
    }

    private func pullCloudFolders(context: ModelContext, sync: CloudKitSyncService) async {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let remoteRecords = await sync.fetchRemoteFolders()
            let existingFolders = try context.fetch(FetchDescriptor<VaultFolder>())
            var foldersById = Dictionary(uniqueKeysWithValues: existingFolders.map { ($0.id, $0) })

            for record in remoteRecords {
                guard let folderId = record["folderId"] as? String else { continue }
                let encryptedName = record["encryptedName"] as? Data ?? Data()
                guard (try? VaultCryptoService.decryptString(encryptedName, using: rootKey)) != nil else {
                    continue
                }
                let sortOrder = record["sortOrder"] as? Int ?? 0
                let updatedAt = record["updatedAt"] as? Date ?? Date()
                let deletedAt = record["deletedAt"] as? Date
                let localRevision = record["localRevision"] as? Int ?? 1

                if let existing = foldersById[folderId] {
                    guard VaultRemoteMergePolicy.shouldApplyRemote(
                        remoteUpdatedAt: updatedAt,
                        remoteRevision: localRevision,
                        localUpdatedAt: existing.updatedAt,
                        localRevision: existing.localRevision,
                        localSyncStatus: existing.syncStatus
                    ) else { continue }
                    existing.encryptedName = encryptedName
                    existing.sortOrder = sortOrder
                    existing.updatedAt = updatedAt
                    existing.deletedAt = deletedAt
                    existing.localRevision = localRevision
                    existing.cloudRecordName = record.recordID.recordName
                    existing.syncStatus = .synced
                } else {
                    let folder = VaultFolder(id: folderId, encryptedName: encryptedName, sortOrder: sortOrder)
                    folder.updatedAt = updatedAt
                    folder.deletedAt = deletedAt
                    folder.localRevision = localRevision
                    folder.cloudRecordName = record.recordID.recordName
                    folder.syncStatus = .synced
                    context.insert(folder)
                    foldersById[folderId] = folder
                }
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func validateLocalStoreForRecoveredRootKey(
        _ rootKey: SymmetricKey,
        context: ModelContext
    ) throws -> VaultRecoveryLocalCleanup {
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        let unreadableItems = items.filter {
            VaultCloudMetadataInspector.classify($0.encryptedMetadata, using: rootKey) != .readable
        }
        guard unreadableItems.allSatisfy({ $0.cloudRecordName?.isEmpty == false && $0.syncStatus == .synced }) else {
            throw NSError(
                domain: "VaultRecovery",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L.string("This device has local changes from another vault that are not backed up. Recovery was stopped without changing the encryption key.")]
            )
        }

        let folders = try context.fetch(FetchDescriptor<VaultFolder>())
        let unreadableFolders = folders.filter {
            (try? VaultCryptoService.decryptString($0.encryptedName, using: rootKey)) == nil
        }
        guard unreadableFolders.allSatisfy({ $0.cloudRecordName?.isEmpty == false && $0.syncStatus == .synced }) else {
            throw NSError(
                domain: "VaultRecovery",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: L.string("This device has local folder changes from another vault that are not backed up. Recovery was stopped without changing the encryption key.")]
            )
        }

        let notes = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
        let unreadableNotes = notes.filter {
            (try? VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: $0.encryptedPayload, using: rootKey)) == nil
        }
        guard unreadableNotes.allSatisfy({ $0.cloudRecordName?.isEmpty == false && $0.syncStatus == .synced }) else {
            throw NSError(
                domain: "VaultRecovery",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: L.string("This device has local note changes from another vault that are not backed up. Recovery was stopped without changing the encryption key.")]
            )
        }

        return VaultRecoveryLocalCleanup(
            items: unreadableItems,
            folders: unreadableFolders,
            notes: unreadableNotes
        )
    }

    private func makeLocalManifest(rootKey: SymmetricKey) throws -> VaultManifest {
        try? VaultCryptoService.syncRootKeyToICloudKeychain()
        let name = try VaultCryptoService.encryptString("Private Vault", using: rootKey)
        let package = try VaultCryptoService.makeRootKeyPackage()
        return VaultManifest(id: UUID().uuidString, encryptedVaultName: name, encryptedRootKeyPackage: package)
    }

    private func makeManifest(from record: CKRecord) -> VaultManifest {
        let manifest = VaultManifest(
            id: record["vaultId"] as? String ?? record.recordID.recordName,
            encryptedVaultName: record["encryptedVaultName"] as? Data ?? Data(),
            encryptedRootKeyPackage: record["encryptedRootKeyPackage"] as? Data ?? Data()
        )
        manifest.schemaVersion = record["schemaVersion"] as? Int ?? 1
        manifest.updatedAt = record["updatedAt"] as? Date ?? Date()
        manifest.syncStatus = .synced
        return manifest
    }

    private func makeThumbnailData(
        from data: Data,
        kind: VaultItemKind,
        originalName: String = "",
        mimeType: String = ""
    ) async -> Data? {
        switch kind {
        case .image:
            guard let image = UIImage(data: data) else { return nil }
            return renderThumbnailData(from: image)
        case .livePhoto:
            guard let package = try? PropertyListDecoder().decode(LivePhotoPackage.self, from: data),
                  let image = UIImage(data: package.stillData) else {
                return nil
            }
            return renderThumbnailData(from: image)
        case .video:
            return await makeVideoThumbnailData(
                from: data,
                preferredExtension: videoFileExtension(originalName: originalName, mimeType: mimeType)
            )
        default:
            return nil
        }
    }

    private func makeVideoThumbnailData(from data: Data, preferredExtension: String?) async -> Data? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension ?? "mov")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let asset = AVURLAsset(url: temporaryURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            for time in videoThumbnailTimes {
                if let image = try? await generateImage(with: generator, at: time),
                   let data = renderThumbnailData(from: UIImage(cgImage: image)) {
                    return data
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private var videoThumbnailTimes: [CMTime] {
        [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime(seconds: 1, preferredTimescale: 600)
        ]
    }

    private func videoFileExtension(originalName: String, mimeType: String) -> String? {
        let nameExtension = (originalName as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameExtension.isEmpty {
            return nameExtension.lowercased()
        }

        let mimeExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
        return mimeExtension?.isEmpty == false ? mimeExtension : nil
    }

    private func generateImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    private func renderThumbnailData(from image: UIImage) -> Data? {
        let target = CGSize(width: 320, height: 320)
        let renderer = UIGraphicsImageRenderer(size: target)
        let rendered = renderer.image { _ in
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.78)
    }
}

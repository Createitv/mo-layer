import Combine
import Foundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum ImportService {
    static let appGroupIdentifier = "group.app.landlady.www.privacy"
    static let sharedInboxDirectoryName = "SharedImports"
    static let sharedImportManifestName = "pending-imports.json"

    struct PendingSharedImport: Identifiable, Equatable {
        let id: String
        let originalName: String
        let mimeType: String
        let typeIdentifier: String
        let byteSize: Int64
        let createdAt: Date
        let fileURL: URL
    }

    private struct SharedImportManifest: Codable {
        var items: [SharedImportManifestItem]
    }

    private struct SharedImportManifestItem: Codable {
        var id: String
        var originalName: String
        var storedFileName: String
        var typeIdentifier: String
        var mimeType: String
        var byteSize: Int64
        var createdAt: Date
    }

    @MainActor
    @discardableResult
    static func importPickerItems(
        _ items: [PhotosPickerItem],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        folderId: String? = nil,
        syncAfterImport: Bool = true,
        progress: ((Bool) -> Void)? = nil
    ) async -> ImportSummary {
        var summary = ImportSummary()
        for item in items {
            if let livePhotoImport = await livePhotoImport(from: item),
               let packageData = try? binaryPropertyListEncoder.encode(livePhotoImport.package) {
                let success = await vaultStore.importData(
                    packageData,
                    originalName: livePhotoImport.originalName,
                    mimeType: "application/vnd.apple.live-photo",
                    source: "Photos",
                    kind: .livePhoto,
                    context: context,
                    sync: sync,
                    folderId: folderId,
                    syncAfterImport: syncAfterImport
                )
                success ? summary.record(.livePhoto) : summary.recordFailure()
                progress?(success)
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self) else {
                summary.recordFailure()
                progress?(false)
                continue
            }
            let contentType = item.supportedContentTypes.first
            let kind: VaultItemKind = contentType?.conforms(to: UTType.movie) == true ? .video : .image
            let name = "Photo-\(Date().timeIntervalSince1970).\(contentType?.preferredFilenameExtension ?? "dat")"
            let success = await vaultStore.importData(
                data,
                originalName: name,
                mimeType: contentType?.preferredMIMEType ?? "application/octet-stream",
                source: "Photos",
                kind: kind,
                context: context,
                sync: sync,
                folderId: folderId,
                syncAfterImport: syncAfterImport
            )
            if success {
                summary.record(kind)
            } else {
                summary.recordFailure()
            }
            progress?(success)
        }
        return summary
    }

    private static var binaryPropertyListEncoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    private struct LivePhotoImport {
        let package: LivePhotoPackage
        let originalName: String
    }

    private static func livePhotoImport(from item: PhotosPickerItem) async -> LivePhotoImport? {
        guard let identifier = item.itemIdentifier else { return nil }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject,
              asset.mediaSubtypes.contains(.photoLive) else {
            return nil
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let photoResource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }),
              let pairedVideoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }

        async let photoData = resourceData(for: photoResource)
        async let videoData = resourceData(for: pairedVideoResource)
        guard let stillData = await photoData,
              let pairedVideoData = await videoData else {
            return nil
        }

        let package = LivePhotoPackage(
            stillData: stillData,
            pairedVideoData: pairedVideoData,
            stillFilename: photoResource.originalFilename,
            pairedVideoFilename: pairedVideoResource.originalFilename
        )
        return LivePhotoImport(package: package, originalName: photoResource.originalFilename)
    }

    private static func resourceData(for resource: PHAssetResource) async -> Data? {
        let fileExtension = (resource.originalFilename as NSString).pathExtension
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "dat" : fileExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: temporaryURL, options: options) { error in
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard error == nil,
                      let data = try? Data(contentsOf: temporaryURL) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    @MainActor
    @discardableResult
    static func importFile(
        url: URL,
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Files",
        folderId: String? = nil,
        syncAfterImport: Bool = true
    ) async -> Bool {
        guard let data = await loadFileData(from: url) else { return false }
        let type = UTType(filenameExtension: url.pathExtension)
        return await vaultStore.importData(
            data,
            originalName: url.lastPathComponent,
            mimeType: type?.preferredMIMEType ?? "application/octet-stream",
            source: source,
            kind: kind(for: type, fileExtension: url.pathExtension),
            context: context,
            sync: sync,
            folderId: folderId,
            syncAfterImport: syncAfterImport
        )
    }

    @MainActor
    static func importFiles(
        urls: [URL],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Files",
        folderId: String? = nil,
        syncAfterImport: Bool = true,
        progress: ((Bool) -> Void)? = nil
    ) async -> ImportSummary {
        var summary = ImportSummary()
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension)
            let kind = kind(for: type, fileExtension: url.pathExtension)
            let success = await importFile(
                url: url,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: source,
                folderId: folderId,
                syncAfterImport: syncAfterImport
            )
            if success {
                summary.record(kind)
            } else {
                summary.recordFailure()
            }
            progress?(success)
        }
        return summary
    }

    private static func loadFileData(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            return try? Data(contentsOf: url)
        }.value
    }

    @MainActor
    static func importLink(
        _ url: URL,
        title: String? = nil,
        source: String,
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService
    ) async {
        await vaultStore.importLink(
            url,
            title: title,
            source: source,
            context: context,
            sync: sync
        )
    }

    @MainActor
    static func consumeSharedImports(
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService
    ) async {
        _ = await importPendingSharedImports(context: context, vaultStore: vaultStore, sync: sync)
    }

    @MainActor
    static func pendingSharedImports() -> [PendingSharedImport] {
        guard let directory = sharedInboxDirectory() else { return [] }
        if let manifest = readManifest(in: directory) {
            return manifest.items.compactMap { item in
                let fileURL = directory.appendingPathComponent(item.storedFileName)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
                return PendingSharedImport(
                    id: item.id,
                    originalName: item.originalName,
                    mimeType: item.mimeType,
                    typeIdentifier: item.typeIdentifier,
                    byteSize: item.byteSize,
                    createdAt: item.createdAt,
                    fileURL: fileURL
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
        }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return urls
            .filter { $0.lastPathComponent != sharedImportManifestName && $0.pathExtension != "urlimport" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .creationDateKey])
                let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
                return PendingSharedImport(
                    id: url.lastPathComponent,
                    originalName: url.lastPathComponent,
                    mimeType: type.preferredMIMEType ?? "application/octet-stream",
                    typeIdentifier: type.identifier,
                    byteSize: Int64(values?.fileSize ?? 0),
                    createdAt: values?.creationDate ?? Date(),
                    fileURL: url
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @MainActor
    static func importPendingSharedImports(
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService
    ) async -> ImportSummary {
        let pending = pendingSharedImports()
        var summary = ImportSummary()
        var failedItems: [PendingSharedImport] = []

        for item in pending {
            let type = UTType(item.typeIdentifier) ?? UTType(filenameExtension: item.fileURL.pathExtension)
            let kind = kind(for: type, fileExtension: item.fileURL.pathExtension)
            let success = await importFile(
                url: item.fileURL,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: "Share Extension"
            )
            if success {
                summary.record(kind)
                try? FileManager.default.removeItem(at: item.fileURL)
            } else {
                summary.recordFailure()
                failedItems.append(item)
            }
        }

        rewriteManifest(for: failedItems)
        return summary
    }

    @MainActor
    static func stageFileForReview(url: URL) -> Bool {
        guard let directory = sharedInboxDirectory() else { return false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let originalName = sanitizedFileName(url.lastPathComponent.isEmpty ? "\(UUID().uuidString).dat" : url.lastPathComponent)
        let storedFileName = "\(UUID().uuidString)-\(originalName)"
        let destination = directory.appendingPathComponent(storedFileName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let type = values?.contentType ?? UTType(filenameExtension: destination.pathExtension) ?? .data
            appendManifestItem(
                SharedImportManifestItem(
                    id: UUID().uuidString,
                    originalName: originalName,
                    storedFileName: storedFileName,
                    typeIdentifier: type.identifier,
                    mimeType: type.preferredMIMEType ?? "application/octet-stream",
                    byteSize: Int64(values?.fileSize ?? 0),
                    createdAt: Date()
                ),
                in: directory
            )
            return true
        } catch {
            return false
        }
    }

    static func discardSharedImports() {
        guard let directory = sharedInboxDirectory() else { return }
        try? FileManager.default.removeItem(at: directory)
        _ = sharedInboxDirectory()
    }

    static func sharedInboxDirectory() -> URL? {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        let directory = base?.appendingPathComponent(sharedInboxDirectoryName, isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func kind(for type: UTType?, fileExtension: String) -> VaultItemKind {
        let lowerExtension = fileExtension.lowercased()
        if lowerExtension == "livephoto" { return .livePhoto }
        if type?.conforms(to: .image) == true { return .image }
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .audio) == true { return .audio }
        if type?.conforms(to: .pdf) == true || type?.conforms(to: .text) == true { return .document }
        if [
            "doc", "docx", "pages", "rtf", "odt",
            "xls", "xlsx", "numbers", "csv", "ods",
            "ppt", "pptx", "key", "odp",
            "txt", "md", "markdown", "json", "xml", "yaml", "yml", "log",
            "swift", "js", "ts", "tsx", "jsx", "html", "css", "py", "java", "kt", "c", "cpp", "h", "m", "mm", "php", "rb", "go", "rs", "sh", "sql",
            "psd", "ai", "indd", "xd", "fig", "sketch",
            "epub", "mobi", "azw", "azw3", "ics", "vcf"
        ].contains(lowerExtension) { return .document }
        if ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "jar", "ipa", "apk"].contains(lowerExtension) { return .archive }
        if type != nil { return .document }
        return .other
    }

    private static func readManifest(in directory: URL) -> SharedImportManifest? {
        let url = directory.appendingPathComponent(sharedImportManifestName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedImportManifest.self, from: data)
    }

    private static func rewriteManifest(for imports: [PendingSharedImport]) {
        guard let directory = sharedInboxDirectory() else { return }
        let url = directory.appendingPathComponent(sharedImportManifestName)
        guard !imports.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let manifest = SharedImportManifest(
            items: imports.map {
                SharedImportManifestItem(
                    id: $0.id,
                    originalName: $0.originalName,
                    storedFileName: $0.fileURL.lastPathComponent,
                    typeIdentifier: $0.typeIdentifier,
                    mimeType: $0.mimeType,
                    byteSize: $0.byteSize,
                    createdAt: $0.createdAt
                )
            }
        )
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func appendManifestItem(_ item: SharedImportManifestItem, in directory: URL) {
        var manifest = readManifest(in: directory) ?? SharedImportManifest(items: [])
        manifest.items.append(item)
        let url = directory.appendingPathComponent(sharedImportManifestName)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        }
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(UUID().uuidString).dat" }
        return trimmed
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
    }
}

@MainActor
final class VaultImportQueue: ObservableObject {
    private static let completedProgressDisplayDuration: UInt64 = 1_200_000_000

    @Published private(set) var progress: VaultImportProgress?
    private var autoDismissTask: Task<Void, Never>?

    var isImporting: Bool {
        progress?.isActive == true
    }

    func importFiles(
        urls: [URL],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Files",
        folderId: String? = nil,
        onComplete: @escaping (ImportSummary) -> Void
    ) {
        guard !urls.isEmpty, !isImporting else { return }
        autoDismissTask?.cancel()
        progress = VaultImportProgress(totalCount: urls.count)

        Task { @MainActor in
            let summary = await ImportService.importFiles(
                urls: urls,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: source,
                folderId: folderId,
                syncAfterImport: false,
                progress: { [weak self] success in
                    self?.recordProgress(success: success)
                }
            )
            finishImport(summary: summary, context: context, vaultStore: vaultStore, sync: sync, onComplete: onComplete)
        }
    }

    func importPickerItems(
        _ items: [PhotosPickerItem],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        folderId: String? = nil,
        onComplete: @escaping (ImportSummary) -> Void
    ) {
        guard !items.isEmpty, !isImporting else { return }
        autoDismissTask?.cancel()
        progress = VaultImportProgress(totalCount: items.count)

        Task { @MainActor in
            let summary = await ImportService.importPickerItems(
                items,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                folderId: folderId,
                syncAfterImport: false,
                progress: { [weak self] success in
                    self?.recordProgress(success: success)
                }
            )
            finishImport(summary: summary, context: context, vaultStore: vaultStore, sync: sync, onComplete: onComplete)
        }
    }

    private func recordProgress(success: Bool) {
        guard var current = progress else { return }
        if success {
            current.recordImported()
        } else {
            current.recordFailure()
        }
        progress = current
    }

    private func finishImport(
        summary: ImportSummary,
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        onComplete: @escaping (ImportSummary) -> Void
    ) {
        if var current = progress {
            current.finish()
            progress = current
        }
        scheduleAutoDismissIfNeeded()
        onComplete(summary)
        Task { @MainActor in
            await vaultStore.syncPendingChanges(context: context, sync: sync)
        }
    }

    private func scheduleAutoDismissIfNeeded() {
        guard progress?.isReadyForAutoDismissal == true else { return }
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.completedProgressDisplayDuration)
            guard !Task.isCancelled, progress?.isReadyForAutoDismissal == true else { return }
            progress = nil
        }
    }
}

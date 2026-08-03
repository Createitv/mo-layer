import Combine
import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum SharedImportDestination: String, CaseIterable, Identifiable {
    case regular
    case innerVault

    var id: String { rawValue }

    var folderId: String? {
        switch self {
        case .regular:
            nil
        case .innerVault:
            VaultStore.innerVaultFolderId
        }
    }

    var title: String {
        switch self {
        case .regular:
            L.string("Regular Vault")
        case .innerVault:
            L.string("Mo Layer")
        }
    }

    var subtitle: String {
        switch self {
        case .regular:
            L.string("Save to the regular vault directory.")
        case .innerVault:
            L.string("Save to the Mo Layer directory.")
        }
    }

    var icon: String {
        switch self {
        case .regular:
            "lock"
        case .innerVault:
            "square.stack.3d.down.right"
        }
    }

    static func from(_ rawValue: String?) -> SharedImportDestination {
        guard let rawValue else { return .regular }
        return SharedImportDestination(rawValue: rawValue) ?? .regular
    }
}

enum ImportService {
    static let appGroupIdentifier = "group.app.landlady.www.privacy"
    static let sharedInboxDirectoryName = "SharedImports"
    static let sharedImportManifestName = "pending-imports.json"

    struct PendingSharedImport: Identifiable, Equatable {
        let id: String
        let batchId: String?
        let originalName: String
        let mimeType: String
        let typeIdentifier: String
        let byteSize: Int64
        let createdAt: Date
        let fileURL: URL
        let destination: SharedImportDestination
    }

    private struct SharedImportManifest: Codable {
        var items: [SharedImportManifestItem]
    }

    private struct SharedImportManifestItem: Codable {
        var id: String
        var batchId: String?
        var originalName: String
        var storedFileName: String
        var typeIdentifier: String
        var mimeType: String
        var byteSize: Int64
        var createdAt: Date
        var destinationRawValue: String?
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
        progress: ((VaultImportProgressEvent) -> Void)? = nil
    ) async -> ImportSummary {
        var summary = ImportSummary()
        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { break }
            let contentType = item.supportedContentTypes.first
            progress?(.currentItem(VaultImportProgressItem(
                displayName: L.format("Photo %d", index + 1),
                kind: contentType?.conforms(to: UTType.movie) == true ? .video : .image,
                phaseText: L.string("Loading current file"),
                progress: 0.12,
                thumbnailData: nil
            )))

            if let livePhotoImport = await livePhotoImport(from: item),
               let packageData = try? binaryPropertyListEncoder.encode(livePhotoImport.package) {
                let captureLocation = await captureLocation(for: item, fallbackData: livePhotoImport.package.stillData)
                progress?(.currentItem(VaultImportProgressItem(
                    displayName: livePhotoImport.originalName,
                    kind: .livePhoto,
                    phaseText: L.string("Encrypting current file"),
                    progress: 0.56,
                    thumbnailData: renderPreviewThumbnailData(from: livePhotoImport.package.stillData)
                )))
                let result = await vaultStore.importData(
                    packageData,
                    originalName: livePhotoImport.originalName,
                    mimeType: "application/vnd.apple.live-photo",
                    source: "Photos",
                    kind: .livePhoto,
                    context: context,
                    sync: sync,
                    folderId: folderId,
                    syncAfterImport: syncAfterImport,
                    saveImmediately: false,
                    captureLocation: captureLocation
                )
                summary.record(result, kind: .livePhoto)
                saveBatchIfNeeded(summary: summary, context: context)
                progress?(.completed(result))
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self) else {
                summary.recordFailure()
                progress?(.completed(.failed))
                continue
            }
            let kind: VaultItemKind = contentType?.conforms(to: UTType.movie) == true ? .video : .image
            let name = "Photo-\(Date().timeIntervalSince1970).\(contentType?.preferredFilenameExtension ?? "dat")"
            let captureLocation = await captureLocation(for: item, fallbackData: data)
            progress?(.currentItem(VaultImportProgressItem(
                displayName: name,
                kind: kind,
                phaseText: L.string("Encrypting current file"),
                progress: 0.56,
                thumbnailData: await previewThumbnailData(from: data, kind: kind, preferredExtension: contentType?.preferredFilenameExtension)
            )))
            let result = await vaultStore.importData(
                data,
                originalName: name,
                mimeType: contentType?.preferredMIMEType ?? "application/octet-stream",
                source: "Photos",
                kind: kind,
                context: context,
                sync: sync,
                folderId: folderId,
                syncAfterImport: syncAfterImport,
                saveImmediately: false,
                captureLocation: captureLocation
            )
            summary.record(result, kind: kind)
            saveBatchIfNeeded(summary: summary, context: context)
            progress?(.completed(result))
        }
        try? context.save()
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

    private struct ParsedGPSLocation {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let capturedAt: Date?
    }

    private static func captureLocation(for item: PhotosPickerItem, fallbackData data: Data?) async -> VaultCaptureLocation? {
        if let identifier = item.itemIdentifier {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = result.firstObject,
               let location = asset.location {
                return await captureLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                    altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                    capturedAt: asset.creationDate ?? location.timestamp
                )
            }
        }

        return await captureLocation(fromImageData: data)
    }

    private static func captureLocation(from data: Data, kind: VaultItemKind) async -> VaultCaptureLocation? {
        if kind == .livePhoto,
           let package = try? PropertyListDecoder().decode(LivePhotoPackage.self, from: data) {
            return await captureLocation(fromImageData: package.stillData)
        }
        guard kind == .image else { return nil }
        return await captureLocation(fromImageData: data)
    }

    private static func captureLocation(fromImageData data: Data?) async -> VaultCaptureLocation? {
        guard let parsed = gpsLocation(fromImageData: data) else { return nil }
        return await captureLocation(
            latitude: parsed.latitude,
            longitude: parsed.longitude,
            horizontalAccuracy: nil,
            altitude: parsed.altitude,
            capturedAt: parsed.capturedAt ?? Date()
        )
    }

    private static func captureLocation(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double?,
        altitude: Double?,
        capturedAt: Date
    ) async -> VaultCaptureLocation {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let address = await reverseGeocodedAddress(for: location)
        return VaultCaptureLocation(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            altitude: altitude,
            capturedAt: capturedAt,
            resolvedAddress: address
        )
    }

    private static func gpsLocation(fromImageData data: Data?) -> ParsedGPSLocation? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = signedCoordinate(
                value: doubleValue(gps[kCGImagePropertyGPSLatitude]),
                reference: gps[kCGImagePropertyGPSLatitudeRef],
                negativeReference: "S"
              ),
              let longitude = signedCoordinate(
                value: doubleValue(gps[kCGImagePropertyGPSLongitude]),
                reference: gps[kCGImagePropertyGPSLongitudeRef],
                negativeReference: "W"
              ) else {
            return nil
        }

        let altitudeValue = doubleValue(gps[kCGImagePropertyGPSAltitude])
        let altitudeReference = doubleValue(gps[kCGImagePropertyGPSAltitudeRef])
        let altitude = altitudeReference == 1 ? altitudeValue.map { -abs($0) } : altitudeValue
        return ParsedGPSLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            capturedAt: gpsTimestamp(from: gps)
        )
    }

    private static func signedCoordinate(value: Double?, reference: Any?, negativeReference: String) -> Double? {
        guard let value else { return nil }
        let referenceText = reference.map { String(describing: $0).uppercased() } ?? ""
        return referenceText == negativeReference ? -abs(value) : abs(value)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func gpsTimestamp(from gps: [CFString: Any]) -> Date? {
        guard let dateStamp = gps[kCGImagePropertyGPSDateStamp].map({ String(describing: $0) }),
              let timeStamp = gps[kCGImagePropertyGPSTimeStamp].map({ String(describing: $0) }) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss.SSS"
        if let date = formatter.date(from: "\(dateStamp) \(timeStamp)") {
            return date
        }

        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: "\(dateStamp) \(timeStamp)")
    }

    private static func reverseGeocodedAddress(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                continuation.resume(returning: placemarks?.first.flatMap(addressText))
            }
        }
    }

    private nonisolated static func addressText(from placemark: CLPlacemark) -> String? {
        let parts = [
            placemark.name,
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ]
        var seen = Set<String>()
        let uniqueParts = parts.compactMap { part -> String? in
            let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
        return uniqueParts.isEmpty ? nil : uniqueParts.joined(separator: ", ")
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
        syncAfterImport: Bool = true,
        saveImmediately: Bool = true
    ) async -> VaultImportResult {
        guard let data = await loadFileData(from: url) else { return .failed }
        let type = UTType(filenameExtension: url.pathExtension)
        let kind = kind(for: type, fileExtension: url.pathExtension)
        let captureLocation = await captureLocation(from: data, kind: kind)
        return await vaultStore.importData(
            data,
            originalName: url.lastPathComponent,
            mimeType: type?.preferredMIMEType ?? "application/octet-stream",
            source: source,
            kind: kind,
            context: context,
            sync: sync,
            folderId: folderId,
            syncAfterImport: syncAfterImport,
            saveImmediately: saveImmediately,
            captureLocation: captureLocation
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
        progress: ((VaultImportProgressEvent) -> Void)? = nil
    ) async -> ImportSummary {
        var summary = ImportSummary()
        for url in urls {
            guard !Task.isCancelled else { break }
            let type = UTType(filenameExtension: url.pathExtension)
            let kind = kind(for: type, fileExtension: url.pathExtension)
            progress?(.currentItem(VaultImportProgressItem(
                displayName: url.lastPathComponent,
                kind: kind,
                phaseText: L.string("Loading current file"),
                progress: 0.12,
                thumbnailData: await previewThumbnailData(from: url, kind: kind)
            )))
            let result = await importFile(
                url: url,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: source,
                folderId: folderId,
                syncAfterImport: syncAfterImport,
                saveImmediately: false
            )
            summary.record(result, kind: kind)
            saveBatchIfNeeded(summary: summary, context: context)
            progress?(.completed(result))
        }
        try? context.save()
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
    static func pendingSharedImports(batchId: String? = nil) -> [PendingSharedImport] {
        guard let directory = sharedInboxDirectory() else { return [] }
        let imports: [PendingSharedImport]
        if let manifest = readManifest(in: directory) {
            imports = manifest.items.compactMap { item in
                let fileURL = directory.appendingPathComponent(item.storedFileName)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
                return PendingSharedImport(
                    id: item.id,
                    batchId: item.batchId,
                    originalName: item.originalName,
                    mimeType: item.mimeType,
                    typeIdentifier: item.typeIdentifier,
                    byteSize: item.byteSize,
                    createdAt: item.createdAt,
                    fileURL: fileURL,
                    destination: SharedImportDestination.from(item.destinationRawValue)
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
        } else {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                return []
            }

            imports = urls
                .filter { $0.lastPathComponent != sharedImportManifestName && $0.pathExtension != "urlimport" }
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .creationDateKey])
                    let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
                    return PendingSharedImport(
                        id: url.lastPathComponent,
                        batchId: nil,
                        originalName: url.lastPathComponent,
                        mimeType: type.preferredMIMEType ?? "application/octet-stream",
                        typeIdentifier: type.identifier,
                        byteSize: Int64(values?.fileSize ?? 0),
                        createdAt: values?.creationDate ?? Date(),
                        fileURL: url,
                        destination: .regular
                    )
                }
                .sorted { $0.createdAt < $1.createdAt }
        }

        guard let batchId else { return imports }
        return imports.filter { $0.batchId == batchId }
    }

    @MainActor
    static func importPendingSharedImports(
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService
    ) async -> ImportSummary {
        await importPendingSharedImports(
            pendingSharedImports(),
            context: context,
            vaultStore: vaultStore,
            sync: sync
        )
    }

    @MainActor
    static func importPendingSharedImports(
        _ pending: [PendingSharedImport],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        folderId: String? = nil,
        syncAfterImport: Bool = true,
        progress: ((VaultImportProgressEvent) -> Void)? = nil
    ) async -> ImportSummary {
        var summary = ImportSummary()
        var failedItems: [PendingSharedImport] = []

        for item in pending {
            guard !Task.isCancelled else { break }
            let type = UTType(item.typeIdentifier) ?? UTType(filenameExtension: item.fileURL.pathExtension)
            let kind = kind(for: type, fileExtension: item.fileURL.pathExtension)
            progress?(.currentItem(VaultImportProgressItem(
                displayName: item.originalName,
                kind: kind,
                phaseText: L.string("Loading current file"),
                progress: 0.12,
                thumbnailData: await previewThumbnailData(from: item.fileURL, kind: kind)
            )))
            let result = await importFile(
                url: item.fileURL,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: "Share Extension",
                folderId: folderId,
                syncAfterImport: syncAfterImport,
                saveImmediately: false
            )
            summary.record(result, kind: kind)
            if result != .failed {
                try? FileManager.default.removeItem(at: item.fileURL)
            } else {
                failedItems.append(item)
            }
            saveBatchIfNeeded(summary: summary, context: context)
            progress?(.completed(result))
        }

        try? context.save()
        rewriteManifestAfterImport(processed: pending, failed: failedItems)
        return summary
    }

    @MainActor
    static func stageFileForReview(url: URL) -> Bool {
        stageFileForReview(url: url, batchId: nil) != nil
    }

    @MainActor
    static func stageFileForReview(url: URL, batchId: String?) -> PendingSharedImport? {
        guard let directory = sharedInboxDirectory() else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let originalName = sanitizedFileName(url.lastPathComponent.isEmpty ? "\(UUID().uuidString).dat" : url.lastPathComponent)
        let storedFileName = "\(UUID().uuidString)-\(originalName)"
        let destination = directory.appendingPathComponent(storedFileName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let type = values?.contentType ?? UTType(filenameExtension: destination.pathExtension) ?? .data
            let item = SharedImportManifestItem(
                id: UUID().uuidString,
                batchId: batchId,
                originalName: originalName,
                storedFileName: storedFileName,
                typeIdentifier: type.identifier,
                mimeType: type.preferredMIMEType ?? "application/octet-stream",
                byteSize: Int64(values?.fileSize ?? 0),
                createdAt: Date(),
                destinationRawValue: SharedImportDestination.regular.rawValue
            )
            appendManifestItem(item, in: directory)
            return PendingSharedImport(
                id: item.id,
                batchId: item.batchId,
                originalName: item.originalName,
                mimeType: item.mimeType,
                typeIdentifier: item.typeIdentifier,
                byteSize: item.byteSize,
                createdAt: item.createdAt,
                fileURL: destination,
                destination: SharedImportDestination.from(item.destinationRawValue)
            )
        } catch {
            return nil
        }
    }

    static func discardSharedImports() {
        guard let directory = sharedInboxDirectory() else { return }
        try? FileManager.default.removeItem(at: directory)
        _ = sharedInboxDirectory()
    }

    static func discardSharedImports(_ imports: [PendingSharedImport]) {
        guard !imports.isEmpty else { return }
        guard let directory = sharedInboxDirectory() else { return }
        let discardedIds = Set(imports.map(\.id))
        for item in imports {
            try? FileManager.default.removeItem(at: item.fileURL)
        }

        let remainingItems = readManifest(in: directory)?.items.filter { !discardedIds.contains($0.id) } ?? []
        guard !remainingItems.isEmpty else {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(sharedImportManifestName))
            return
        }

        let manifest = SharedImportManifest(items: remainingItems)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: directory.appendingPathComponent(sharedImportManifestName), options: .atomic)
        }
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

    private static func previewThumbnailData(from url: URL, kind: VaultItemKind) async -> Data? {
        switch kind {
        case .image:
            guard let data = try? Data(contentsOf: url) else { return nil }
            return renderPreviewThumbnailData(from: data)
        case .video:
            return await videoPreviewThumbnailData(from: url)
        default:
            return nil
        }
    }

    private static func previewThumbnailData(from data: Data, kind: VaultItemKind, preferredExtension: String?) async -> Data? {
        switch kind {
        case .image:
            return renderPreviewThumbnailData(from: data)
        case .video:
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(preferredExtension?.isEmpty == false ? preferredExtension! : "mov")
            do {
                try data.write(to: temporaryURL, options: .atomic)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                return await videoPreviewThumbnailData(from: temporaryURL)
            } catch {
                return nil
            }
        default:
            return nil
        }
    }

    private static func renderPreviewThumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return renderPreviewThumbnailData(from: image)
    }

    private static func renderPreviewThumbnailData(from image: UIImage) -> Data? {
        let targetSize = CGSize(width: 160, height: 160)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.jpegData(withCompressionQuality: 0.68) { _ in
            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (targetSize.width - size.width) / 2, y: (targetSize.height - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }

    private static func videoPreviewThumbnailData(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        for time in videoPreviewThumbnailTimes {
            let thumbnailData: Data? = await withCheckedContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                    guard let image else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: renderPreviewThumbnailData(from: UIImage(cgImage: image)))
                }
            }
            if let data = thumbnailData {
                return data
            }
        }

        return nil
    }

    private static var videoPreviewThumbnailTimes: [CMTime] {
        [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime(seconds: 1, preferredTimescale: 600)
        ]
    }

    @MainActor
    private static func saveBatchIfNeeded(summary: ImportSummary, context: ModelContext) {
        if VaultImportBatchPolicy.shouldSave(afterImportedCount: summary.importedCount) {
            try? context.save()
        }
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
                    batchId: $0.batchId,
                    originalName: $0.originalName,
                    storedFileName: $0.fileURL.lastPathComponent,
                    typeIdentifier: $0.typeIdentifier,
                    mimeType: $0.mimeType,
                    byteSize: $0.byteSize,
                    createdAt: $0.createdAt,
                    destinationRawValue: $0.destination.rawValue
                )
            }
        )
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func rewriteManifestAfterImport(processed: [PendingSharedImport], failed: [PendingSharedImport]) {
        guard let directory = sharedInboxDirectory() else { return }
        let processedIds = Set(processed.map(\.id))
        let failedIds = Set(failed.map(\.id))
        let existingItems = readManifest(in: directory)?.items ?? []
        let remainingItems = existingItems.filter { item in
            !processedIds.contains(item.id) || failedIds.contains(item.id)
        }
        guard !remainingItems.isEmpty else {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(sharedImportManifestName))
            return
        }
        let manifest = SharedImportManifest(items: remainingItems)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: directory.appendingPathComponent(sharedImportManifestName), options: .atomic)
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
    private var importTask: Task<Void, Never>?

    var isImporting: Bool {
        progress?.isActive == true
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        if var current = progress {
            current.finish()
            progress = current
        }
        scheduleAutoDismissIfNeeded()
    }

    func importFiles(
        urls: [URL],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Files",
        folderId: String? = nil,
        syncAfterImportCompletion: Bool = true,
        onComplete: @escaping (ImportSummary) -> Void
    ) {
        guard !urls.isEmpty, !isImporting else { return }
        autoDismissTask?.cancel()
        importTask?.cancel()
        progress = VaultImportProgress(totalCount: urls.count)

        importTask = Task { @MainActor in
            let summary = await ImportService.importFiles(
                urls: urls,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: source,
                folderId: folderId,
                syncAfterImport: false,
                progress: { [weak self] event in
                    self?.recordProgress(event)
                }
            )
            guard !Task.isCancelled else { return }
            finishImport(summary: summary, context: context, vaultStore: vaultStore, sync: sync, syncAfterImportCompletion: syncAfterImportCompletion, onComplete: onComplete)
        }
    }

    func importPickerItems(
        _ items: [PhotosPickerItem],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        folderId: String? = nil,
        syncAfterImportCompletion: Bool = true,
        onComplete: @escaping (ImportSummary) -> Void
    ) {
        guard !items.isEmpty, !isImporting else { return }
        autoDismissTask?.cancel()
        importTask?.cancel()
        progress = VaultImportProgress(totalCount: items.count)

        importTask = Task { @MainActor in
            let summary = await ImportService.importPickerItems(
                items,
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                folderId: folderId,
                syncAfterImport: false,
                progress: { [weak self] event in
                    self?.recordProgress(event)
                }
            )
            guard !Task.isCancelled else { return }
            finishImport(summary: summary, context: context, vaultStore: vaultStore, sync: sync, syncAfterImportCompletion: syncAfterImportCompletion, onComplete: onComplete)
        }
    }

    private func recordProgress(_ event: VaultImportProgressEvent) {
        guard var current = progress else { return }
        switch event {
        case .currentItem(let item):
            current.updateCurrentItem(item)
        case .completed(let result):
            current.record(result)
        }
        progress = current
    }

    private func finishImport(
        summary: ImportSummary,
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        syncAfterImportCompletion: Bool,
        onComplete: @escaping (ImportSummary) -> Void
    ) {
        if var current = progress {
            current.finish()
            progress = current
        }
        importTask = nil
        scheduleAutoDismissIfNeeded()
        onComplete(summary)
        guard syncAfterImportCompletion else { return }
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

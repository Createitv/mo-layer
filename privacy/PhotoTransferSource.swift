import AVFoundation
import Foundation
import ImageIO
import Photos
import OSLog
import UniformTypeIdentifiers

struct StagedPhotoTransfer {
    var directory: URL
    var files: [URL]
    var names: [String]
    var kind: VaultItemKind
    var mimeType: String
    var capturedAt: Date?
    var modifiedAt: Date?
    var location: VaultCaptureLocation?
    var preservesAllResources = true

    func remove() { try? FileManager.default.removeItem(at: directory) }
    func payload() async throws -> Data {
        if kind == .video || kind == .livePhoto {
            let videoURL = files[kind == .livePhoto ? 1 : 0]
            guard try await AVURLAsset(url: videoURL).load(.isPlayable) else { throw PhotoTransferSource.SourceError.emptyResource }
        }
        let files = files
        let names = names
        let isLive = kind == .livePhoto
        let needsImage = kind == .image || isLive
        return try await Task.detached(priority: .userInitiated) {
            let still = try Data(contentsOf: files[0], options: .mappedIfSafe)
            if needsImage { try PhotoTransferSource.validateImageData(still) }
            guard isLive else { return still }
            let video = try Data(contentsOf: files[1], options: .mappedIfSafe)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            return try encoder.encode(LivePhotoPackage(stillData: still, pairedVideoData: video, stillFilename: names[0], pairedVideoFilename: names[1]))
        }.value
    }
}

enum PhotoTransferSource {
    private static let logger = Logger(subsystem: "app.landlady.www.privacy", category: "PhotoTransfer")

    struct ResourceSelection: Equatable {
        let indices: [Int]
        let kind: VaultItemKind
        let preservesAllResources: Bool
    }

    /// Import the current rendered version, without treating its edit history or
    /// alternate representations as a reason to reject the entire asset.
    static func selection(resources: [PHAssetResourceType], live: Bool, video: Bool = false) throws -> ResourceSelection {
        func index(_ type: PHAssetResourceType) -> Int? {
            let matches = resources.indices.filter { resources[$0] == type }
            return matches.count == 1 ? matches[0] : nil
        }
        let indices: [Int]
        let kind: VaultItemKind
        if video {
            guard let selected = index(.fullSizeVideo) ?? index(.video) else { throw SourceError.unsupportedResources }
            indices = [selected]
            kind = .video
        } else if live, let still = index(.fullSizePhoto), let motion = index(.fullSizePairedVideo) {
            indices = [still, motion]
            kind = .livePhoto
        } else if let current = index(.fullSizePhoto) {
            // Never pair an edited still with the original, unedited video.
            indices = [current]
            kind = .image
        } else if live, let still = index(.photo), let motion = index(.pairedVideo) {
            indices = [still, motion]
            kind = .livePhoto
        } else if !live, let still = index(.photo) ?? index(.alternatePhoto) {
            indices = [still]
            kind = .image
        } else {
            throw SourceError.unsupportedResources
        }
        return ResourceSelection(indices: indices, kind: kind,
            preservesAllResources: supports(resources: resources, live: live))
    }
    enum SourceError: LocalizedError {
        case inaccessible, unsupportedResources, emptyResource, sourceChanged
        var errorDescription: String? {
            switch self {
            case .inaccessible: "Allow access to the selected photos in Settings, then retry. Originals have not been deleted."
            case .unsupportedResources: "No readable photo or video resource was found. The original has been kept."
            case .emptyResource: "The original could not be downloaded completely. Please retry."
            case .sourceChanged: "The system original changed after import. It has been kept; import the updated photo again."
            }
        }
    }

    nonisolated static func validateImageData(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 16
              ] as CFDictionary) != nil else { throw CocoaError(.fileReadCorruptFile) }
    }

    static func supports(resources: [PHAssetResourceType], live: Bool) -> Bool {
        if live { return resources.count == 2 && resources.contains(.photo) && resources.contains(.pairedVideo) }
        return resources.count == 1 && (resources[0] == .photo || resources[0] == .video)
    }

    static func stage(identifier: String) async throws -> StagedPhotoTransfer {
        try Task.checkCancellation()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { throw SourceError.inaccessible }
        let resources = PHAssetResource.assetResources(for: asset)
        let live = asset.mediaSubtypes.contains(.photoLive)
        let types = resources.map(\.type)
        logger.info("Inspect import resource types=\(types.map(\.rawValue).description, privacy: .public)")
        let selection = try selection(resources: types, live: live, video: asset.mediaType == .video)
        let ordered = selection.indices.map { resources[$0] }
        logger.info("Import resource types=\(types.map(\.rawValue).description, privacy: .public) selected=\(selection.indices.description, privacy: .public) preservesAll=\(selection.preservesAllResources)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTransfer-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        do {
            var files: [URL] = []
            for (index, resource) in ordered.enumerated() {
                try Task.checkCancellation()
                let ext = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "resource"
                let url = directory.appendingPathComponent("\(index).\(ext)")
                try await write(resource, to: url)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 else { throw SourceError.emptyResource }
                files.append(url)
            }
            try Task.checkCancellation()
            guard let current = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
                  current.modificationDate == asset.modificationDate else { throw SourceError.sourceChanged }
            let location = asset.location.map {
                VaultCaptureLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                    horizontalAccuracy: $0.horizontalAccuracy, altitude: $0.altitude,
                    capturedAt: asset.creationDate ?? $0.timestamp, resolvedAddress: nil)
            }
            return StagedPhotoTransfer(directory: directory, files: files, names: ordered.map(\.originalFilename),
                kind: selection.kind,
                mimeType: selection.kind == .livePhoto ? "application/vnd.apple.live-photo" : (UTType(ordered[0].uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream"),
                capturedAt: asset.creationDate, modifiedAt: asset.modificationDate, location: location,
                preservesAllResources: selection.preservesAllResources)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        // requestData supports cancellation, unlike writeData. Stream chunks to a protected file.
        let request = PhotoResourceDownload(url: url)
        try await withTaskCancellationHandler {
            try await request.start(resource: resource, options: options)
        } onCancel: { request.cancel() }
    }

    static func clearAbandonedStaging() {
        let directory = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix("PhotoTransfer-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// PhotoKit may call back on arbitrary queues; cancellation and file writes share a lock.
private final class PhotoResourceDownload: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated private let url: URL
    nonisolated(unsafe) private var handle: FileHandle?
    nonisolated(unsafe) private var requestID: PHAssetResourceDataRequestID?
    nonisolated(unsafe) private var cancelled = false
    nonisolated(unsafe) private var writeError: Error?

    nonisolated init(url: URL) { self.url = url }
    nonisolated func start(resource: PHAssetResource, options: PHAssetResourceRequestOptions) async throws {
        try Data().write(to: url, options: [.completeFileProtection])
        let file = try FileHandle(forWritingTo: url)
        lock.withLock { handle = file }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { [self] data in
                lock.withLock {
                    guard !cancelled, writeError == nil else { return }
                    do { try handle?.write(contentsOf: data) } catch { writeError = error }
                }
            } completionHandler: { [self] error in
                let result: Error? = lock.withLock {
                    do { try handle?.close() } catch { if writeError == nil { writeError = error } }
                    handle = nil
                    return cancelled ? CancellationError() : (writeError ?? error)
                }
                if let result { continuation.resume(throwing: result) } else { continuation.resume() }
            }
            let shouldCancel = lock.withLock { requestID = id; return cancelled }
            if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
    }
    nonisolated func cancel() {
        let id = lock.withLock { cancelled = true; return requestID }
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
}

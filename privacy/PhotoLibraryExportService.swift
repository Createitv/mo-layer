import Foundation
import Photos
import SwiftData

enum PhotoLibraryExportResult: Equatable {
    case saved
    case savedMultiple(Int)
    case partiallySaved(saved: Int, failed: Int)
    case unsupported
    case permissionDenied
    case failed(String)

    var title: String {
        switch self {
        case .saved, .savedMultiple:
            L.string("Saved to Photos")
        case .partiallySaved:
            L.string("Unable to Save")
        case .unsupported:
            L.string("Unable to Save")
        case .permissionDenied:
            L.string("Photo Library Access Needed")
        case .failed:
            L.string("Unable to Save")
        }
    }

    var message: String {
        switch self {
        case .saved:
            L.string("The item was saved to your photo library.")
        case .savedMultiple(let count):
            L.format("Saved %d item(s) to Photos.", count)
        case .partiallySaved(let saved, let failed):
            L.format("Saved %d item(s) to Photos. %d item(s) could not be saved.", saved, failed)
        case .unsupported:
            L.string("This item cannot be saved to Photos.")
        case .permissionDenied:
            L.string("Allow photo library add access in iPhone Settings to save this item.")
        case .failed(let message):
            message
        }
    }
}

enum PhotoLibraryExportService {
    static func canSaveToPhotoLibrary(kind: VaultItemKind) -> Bool {
        kind == .image || kind == .livePhoto || kind == .video
    }

    @MainActor
    static func save(
        item: VaultItem,
        vaultStore: VaultStore,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async -> PhotoLibraryExportResult {
        guard canSaveToPhotoLibrary(kind: item.kind) else {
            return .unsupported
        }

        let authorization = await requestAddOnlyAuthorizationIfNeeded()
        guard authorization == .authorized || authorization == .limited else {
            return .permissionDenied
        }

        do {
            try await saveAsset(
                item,
                vaultStore: vaultStore,
                context: context,
                sync: sync
            )
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @MainActor
    static func save(
        items: [VaultItem],
        vaultStore: VaultStore,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async -> PhotoLibraryExportResult {
        let supportedItems = items.filter { canSaveToPhotoLibrary(kind: $0.kind) }
        guard !supportedItems.isEmpty else {
            return .unsupported
        }

        let authorization = await requestAddOnlyAuthorizationIfNeeded()
        guard authorization == .authorized || authorization == .limited else {
            return .permissionDenied
        }

        var savedCount = 0
        var failedCount = 0
        for item in supportedItems {
            do {
                try await saveAsset(
                    item,
                    vaultStore: vaultStore,
                    context: context,
                    sync: sync
                )
                savedCount += 1
            } catch {
                failedCount += 1
            }
        }

        if savedCount > 0, failedCount == 0 {
            return supportedItems.count == 1 ? .saved : .savedMultiple(savedCount)
        }
        if savedCount > 0 {
            return .partiallySaved(saved: savedCount, failed: failedCount)
        }
        return .failed(L.string("No selected photos or videos could be saved to Photos."))
    }

    private static func requestAddOnlyAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    @MainActor
    private static func saveAsset(
        _ item: VaultItem,
        vaultStore: VaultStore,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async throws {
        switch item.kind {
        case .image, .video:
            let url = try await vaultStore.decryptedTemporaryURL(for: item, context: context, sync: sync)
            try await saveAsset(at: url, kind: item.kind)
        case .livePhoto:
            let urls = try await vaultStore.decryptedLivePhotoResourceURLs(for: item, context: context, sync: sync)
            guard urls.count >= 2 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try await saveLivePhoto(stillURL: urls[0], pairedVideoURL: urls[1])
        case .audio, .document, .archive, .link, .other:
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
    }

    private static func saveAsset(at url: URL, kind: VaultItemKind) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                switch kind {
                case .image:
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                case .video:
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                case .livePhoto, .audio, .document, .archive, .link, .other:
                    break
                }
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    private static func saveLivePhoto(stillURL: URL, pairedVideoURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: stillURL, options: nil)
                request.addResource(with: .pairedVideo, fileURL: pairedVideoURL, options: nil)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }
}

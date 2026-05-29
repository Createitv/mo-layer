import Foundation
import Photos
import SwiftData

enum PhotoLibraryExportResult: Equatable {
    case saved
    case unsupported
    case permissionDenied
    case failed(String)

    var title: String {
        switch self {
        case .saved:
            L.string("Saved to Photos")
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
        kind == .image || kind == .video
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
            let url = try await vaultStore.decryptedTemporaryURL(for: item, context: context, sync: sync)
            try await saveAsset(at: url, kind: item.kind)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
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
}

import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum ImportService {
    static let appGroupIdentifier = "group.app.landlady.www.privacy"
    static let sharedInboxDirectoryName = "SharedImports"

    @MainActor
    @discardableResult
    static func importPickerItems(
        _ items: [PhotosPickerItem],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService
    ) async -> ImportSummary {
        var summary = ImportSummary()
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
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
                sync: sync
            )
            if success {
                summary.record(kind)
            } else {
                summary.recordFailure()
            }
        }
        return summary
    }

    @MainActor
    @discardableResult
    static func importFile(
        url: URL,
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Files"
    ) async -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else { return false }
        let type = UTType(filenameExtension: url.pathExtension)
        return await vaultStore.importData(
            data,
            originalName: url.lastPathComponent,
            mimeType: type?.preferredMIMEType ?? "application/octet-stream",
            source: source,
            kind: kind(for: type, fileExtension: url.pathExtension),
            context: context,
            sync: sync
        )
    }

    @MainActor
    static func importFiles(
        urls: [URL],
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Files"
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
                source: source
            )
            if success {
                summary.record(kind)
            } else {
                summary.recordFailure()
            }
        }
        return summary
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
        guard let directory = sharedInboxDirectory() else { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls {
            if url.pathExtension == "urlimport",
               let value = try? String(contentsOf: url, encoding: .utf8),
               let sharedURL = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                await importLink(sharedURL, source: "Share Extension", context: context, vaultStore: vaultStore, sync: sync)
                try? FileManager.default.removeItem(at: url)
                continue
            }

            await importFile(url: url, context: context, vaultStore: vaultStore, sync: sync, source: "Share Extension")
            try? FileManager.default.removeItem(at: url)
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
        if type?.conforms(to: .image) == true { return .image }
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .audio) == true { return .audio }
        if type?.conforms(to: .pdf) == true || type?.conforms(to: .text) == true { return .document }
        if ["zip", "rar", "7z", "tar", "gz"].contains(lowerExtension) { return .archive }
        if type != nil { return .document }
        return .other
    }
}

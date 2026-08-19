import Foundation
import Observation
import SwiftData

enum AlbumMediaKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case photos
    case videos

    var id: String { rawValue }
}

struct AlbumMediaScope: Equatable, Hashable, Sendable {
    let isInnerVaultActive: Bool
    let filter: AlbumMediaKindFilter
    let favoritesOnly: Bool
}

struct AlbumMediaCursor: Equatable, Sendable {
    let createdAt: Date
    let id: String
}

enum AlbumMediaPageMergePolicy {
    static func merge(existingIDs: [String], incomingIDs: [String]) -> [String] {
        var seen = Set(existingIDs)
        var result = existingIDs
        result.reserveCapacity(existingIDs.count + incomingIDs.count)
        for id in incomingIDs where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}

enum AlbumMediaLoadTriggerPolicy {
    static func shouldLoadMore(
        maxRequestedIndex: Int,
        loadedCount: Int,
        estimatedVisibleCount: Int
    ) -> Bool {
        guard loadedCount > 0, maxRequestedIndex >= 0 else { return false }
        let threshold = max(estimatedVisibleCount * 2, 1)
        return maxRequestedIndex >= max(loadedCount - threshold, 0)
    }
}

enum AlbumMediaPagingRequestPolicy {
    static func canStart(isLoading: Bool, hasMore: Bool) -> Bool {
        !isLoading && hasMore
    }
}

enum AlbumMediaCursorPolicy {
    static func cursor(createdAt: Date, id: String) -> AlbumMediaCursor {
        AlbumMediaCursor(createdAt: createdAt, id: id)
    }
}

struct AlbumLibraryCountSnapshot: Equatable, Sendable {
    var totalActive = 0
    var album = 0
    var audio = 0
    var documents = 0
    var links = 0
    var albumFavorites = 0
    var regularSpace = 0
    var innerSpace = 0

    static let empty = AlbumLibraryCountSnapshot()
}

enum AlbumLibraryCountQuery {
    @MainActor
    static func fetch(context: ModelContext, isInnerVaultActive: Bool) throws -> AlbumLibraryCountSnapshot {
        let innerFolderID = VaultStore.innerVaultFolderId
        let imageKind = VaultItemKind.image.rawValue
        let livePhotoKind = VaultItemKind.livePhoto.rawValue
        let videoKind = VaultItemKind.video.rawValue
        let audioKind = VaultItemKind.audio.rawValue
        let documentKind = VaultItemKind.document.rawValue
        let archiveKind = VaultItemKind.archive.rawValue
        let otherKind = VaultItemKind.other.rawValue
        let linkKind = VaultItemKind.link.rawValue

        let allActive = FetchDescriptor<VaultItem>(predicate: #Predicate { item in
            item.deletedAt == nil && item.kindRawValue != linkKind
        })
        func count(kindRawValue: String, favoritesOnly: Bool = false) throws -> Int {
            let descriptor: FetchDescriptor<VaultItem>
            if isInnerVaultActive {
                if favoritesOnly {
                    descriptor = FetchDescriptor(predicate: #Predicate { item in
                        item.deletedAt == nil && item.folderId == innerFolderID && item.isFavorite &&
                            item.kindRawValue == kindRawValue
                    })
                } else {
                    descriptor = FetchDescriptor(predicate: #Predicate { item in
                        item.deletedAt == nil && item.folderId == innerFolderID &&
                            item.kindRawValue == kindRawValue
                    })
                }
            } else if favoritesOnly {
                descriptor = FetchDescriptor(predicate: #Predicate { item in
                    item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID) && item.isFavorite &&
                        item.kindRawValue == kindRawValue
                })
            } else {
                descriptor = FetchDescriptor(predicate: #Predicate { item in
                    item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID) &&
                        item.kindRawValue == kindRawValue
                })
            }
            return try context.fetchCount(descriptor)
        }
        let regular: FetchDescriptor<VaultItem> = FetchDescriptor(predicate: #Predicate { item in
            item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID)
        })
        let inner: FetchDescriptor<VaultItem> = FetchDescriptor(predicate: #Predicate { item in
            item.deletedAt == nil && item.folderId == innerFolderID
        })

        let imageCount = try count(kindRawValue: imageKind)
        let livePhotoCount = try count(kindRawValue: livePhotoKind)
        let videoCount = try count(kindRawValue: videoKind)
        let favoriteCount = try count(kindRawValue: imageKind, favoritesOnly: true)
            + count(kindRawValue: livePhotoKind, favoritesOnly: true)
            + count(kindRawValue: videoKind, favoritesOnly: true)

        return AlbumLibraryCountSnapshot(
            totalActive: try context.fetchCount(allActive),
            album: imageCount + livePhotoCount + videoCount,
            audio: try count(kindRawValue: audioKind),
            documents: try count(kindRawValue: documentKind)
                + count(kindRawValue: archiveKind)
                + count(kindRawValue: otherKind),
            links: try count(kindRawValue: linkKind),
            albumFavorites: favoriteCount,
            regularSpace: try context.fetchCount(regular),
            innerSpace: try context.fetchCount(inner)
        )
    }
}

@MainActor
@Observable
final class AlbumMediaPagingController {
    static let pageSize = 200

    private(set) var items: [VaultItem] = []
    private(set) var hasMore = true
    private(set) var isInitialLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?

    private var scope: AlbumMediaScope?
    private var cursor: AlbumMediaCursor?
    private var generation = 0

    func loadFirstPage(scope: AlbumMediaScope, context: ModelContext) async {
        generation &+= 1
        let requestGeneration = generation
        self.scope = scope
        cursor = nil
        items = []
        hasMore = true
        error = nil
        isInitialLoading = true
        defer {
            if requestGeneration == generation { isInitialLoading = false }
        }

        do {
            let page = try Self.fetchPage(scope: scope, cursor: nil, limit: Self.pageSize, context: context)
            guard requestGeneration == generation, self.scope == scope else { return }
            items = page.items
            hasMore = page.hasMore
            cursor = page.items.last.map { AlbumMediaCursorPolicy.cursor(createdAt: $0.createdAt, id: $0.id) }
        } catch {
            guard requestGeneration == generation else { return }
            self.error = error.localizedDescription
            hasMore = false
        }
    }

    func loadNextPageIfNeeded(context: ModelContext) async {
        guard let scope,
              AlbumMediaPagingRequestPolicy.canStart(isLoading: isLoadingMore || isInitialLoading, hasMore: hasMore) else {
            return
        }
        let requestGeneration = generation
        isLoadingMore = true
        error = nil
        defer {
            if requestGeneration == generation { isLoadingMore = false }
        }

        do {
            let page = try Self.fetchPage(scope: scope, cursor: cursor, limit: Self.pageSize, context: context)
            guard requestGeneration == generation, self.scope == scope else { return }
            let existingByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let incomingByID = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
            let mergedIDs = AlbumMediaPageMergePolicy.merge(
                existingIDs: items.map(\.id),
                incomingIDs: page.items.map(\.id)
            )
            items = mergedIDs.compactMap { incomingByID[$0] ?? existingByID[$0] }
            hasMore = page.hasMore
            cursor = page.items.last.map { AlbumMediaCursorPolicy.cursor(createdAt: $0.createdAt, id: $0.id) } ?? cursor
        } catch {
            guard requestGeneration == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func refreshPreservingLoadedRange(context: ModelContext) async {
        guard let scope else { return }
        let requestedCount = max(items.count, Self.pageSize)
        generation &+= 1
        let requestGeneration = generation
        cursor = nil
        error = nil
        isInitialLoading = items.isEmpty
        isLoadingMore = !items.isEmpty
        defer {
            if requestGeneration == generation {
                isInitialLoading = false
                isLoadingMore = false
            }
        }

        do {
            let page = try Self.fetchPage(scope: scope, cursor: nil, limit: requestedCount, context: context)
            guard requestGeneration == generation, self.scope == scope else { return }
            items = page.items
            hasMore = page.hasMore
            cursor = page.items.last.map { AlbumMediaCursorPolicy.cursor(createdAt: $0.createdAt, id: $0.id) }
        } catch {
            guard requestGeneration == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private struct Page {
        let items: [VaultItem]
        let hasMore: Bool
    }

    private static func fetchPage(
        scope: AlbumMediaScope,
        cursor: AlbumMediaCursor?,
        limit: Int,
        context: ModelContext
    ) throws -> Page {
        let safeLimit = max(limit, 1)
        let kinds: [VaultItemKind]
        switch scope.filter {
        case .all:
            kinds = [.image, .livePhoto, .video]
        case .photos:
            kinds = [.image, .livePhoto]
        case .videos:
            kinds = [.video]
        }

        var fetched: [VaultItem] = []
        for kind in kinds {
            fetched.append(contentsOf: try fetchKind(
                kind.rawValue,
                scope: scope,
                cursor: cursor,
                limit: safeLimit + 1,
                context: context
            ))
        }
        fetched.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
        return Page(items: Array(fetched.prefix(safeLimit)), hasMore: fetched.count > safeLimit)
    }

    private static func fetchKind(
        _ kindRawValue: String,
        scope: AlbumMediaScope,
        cursor: AlbumMediaCursor?,
        limit: Int,
        context: ModelContext
    ) throws -> [VaultItem] {
        let innerFolderID = VaultStore.innerVaultFolderId
        let predicate: Predicate<VaultItem>

        if let cursor {
            let cursorDate = cursor.createdAt
            let cursorID = cursor.id
            if scope.isInnerVaultActive {
                if scope.favoritesOnly {
                    predicate = #Predicate { item in
                        item.deletedAt == nil && item.folderId == innerFolderID && item.isFavorite &&
                            item.kindRawValue == kindRawValue &&
                            (item.createdAt < cursorDate || (item.createdAt == cursorDate && item.id > cursorID))
                    }
                } else {
                    predicate = #Predicate { item in
                        item.deletedAt == nil && item.folderId == innerFolderID &&
                            item.kindRawValue == kindRawValue &&
                            (item.createdAt < cursorDate || (item.createdAt == cursorDate && item.id > cursorID))
                    }
                }
            } else if scope.favoritesOnly {
                predicate = #Predicate { item in
                    item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID) && item.isFavorite &&
                        item.kindRawValue == kindRawValue &&
                        (item.createdAt < cursorDate || (item.createdAt == cursorDate && item.id > cursorID))
                }
            } else {
                predicate = #Predicate { item in
                    item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID) &&
                        item.kindRawValue == kindRawValue &&
                        (item.createdAt < cursorDate || (item.createdAt == cursorDate && item.id > cursorID))
                }
            }
        } else if scope.isInnerVaultActive {
            if scope.favoritesOnly {
                predicate = #Predicate { item in
                    item.deletedAt == nil && item.folderId == innerFolderID && item.isFavorite &&
                        item.kindRawValue == kindRawValue
                }
            } else {
                predicate = #Predicate { item in
                    item.deletedAt == nil && item.folderId == innerFolderID && item.kindRawValue == kindRawValue
                }
            }
        } else if scope.favoritesOnly {
            predicate = #Predicate { item in
                item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID) && item.isFavorite &&
                    item.kindRawValue == kindRawValue
            }
        } else {
            predicate = #Predicate { item in
                item.deletedAt == nil && (item.folderId == nil || item.folderId != innerFolderID) && item.kindRawValue == kindRawValue
            }
        }

        var descriptor = FetchDescriptor<VaultItem>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\VaultItem.createdAt, order: .reverse),
                SortDescriptor(\VaultItem.id, order: .forward)
            ]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}

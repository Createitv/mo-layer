import XCTest
import SwiftUI
@testable import privacy

@MainActor
final class AlbumGridBatchUpdateTests: XCTestCase {
    private func grid(_ items: [VaultItem]) -> AlbumZoomableMediaGrid {
        AlbumZoomableMediaGrid(
            items: items, columnCount: .constant(3), contentHeight: .constant(600),
            isSelectionMode: false, selectedItemIds: [],
            cachedThumbnailProvider: { _ in nil }, videoDurationProvider: { _ in nil },
            thumbnailProvider: { _ in nil }, visibleItemIDsDidChange: { _ in },
            loadMoreAction: {}, openAction: { _ in }, toggleSelectionAction: { _ in },
            enterSelectionAction: { _ in }
        )
    }

    func testOffscreenEmptyGridLoadsFirstTwoHundredItems() {
        let coordinator = grid([]).makeCoordinator()
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        view.dataSource = coordinator
        coordinator.reloadDataIfNeeded(view)
        let items = (0..<200).map { _ in VaultItem(kind: .image, encryptedMetadata: Data(), byteSize: 1) }
        coordinator.parent = grid(items)
        // Updating SwiftUI inputs must not expose the new count before the UIKit transaction.
        XCTAssertEqual(coordinator.collectionView(view, numberOfItemsInSection: 0), 0)
        coordinator.reloadDataIfNeeded(view)
        XCTAssertEqual(view.numberOfItems(inSection: 0), 200)
        coordinator.parent = grid(items + [VaultItem(kind: .image, encryptedMetadata: Data(), byteSize: 1)])
        XCTAssertEqual(coordinator.collectionView(view, numberOfItemsInSection: 0), 200)
        coordinator.reloadDataIfNeeded(view)
        XCTAssertEqual(view.numberOfItems(inSection: 0), 201)
        coordinator.parent = grid([])
        coordinator.reloadDataIfNeeded(view)
        XCTAssertEqual(view.numberOfItems(inSection: 0), 0)
    }
}

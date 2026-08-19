# Album Lazy Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the album's all-at-once presentation with an automatically paged vertical UICollectionView, 1/3/5/7-column anchored pinch zoom, and a single-item media preview without previous/next navigation.

**Architecture:** Add a focused SwiftData paging controller whose public state is the currently loaded album page sequence, keep the existing UIKit collection-view bridge for cell reuse and thumbnail prefetch, and move album zoom to discrete column counts with an item anchor. The home view consumes paged album items while retaining the existing non-album presentation, and the full-screen preview owns exactly one selected item.

**Tech Stack:** Swift 5 language mode, SwiftUI, UIKit, SwiftData, Observation, AVFoundation, Swift Testing, Xcode `xcodebuild`.

**Spec:** `docs/superpowers/specs/2026-08-19-album-lazy-grid-design.md`

## Global Constraints

- The album is vertically continuous and has no previous/next controls.
- Album page size is 200 items, with prefetch beginning approximately two screens before the loaded tail.
- Supported album column counts are exactly 1, 3, 5, and 7; a new install defaults to 3 and persists the last settled count.
- A pinch layout change preserves the item under the gesture center and its relative viewport position.
- Grid scrolling and zooming must not create an `AVPlayer` or decode a full-resolution original.
- Preserve filtering, favorites, Mo Layer, long-press selection, sweep selection, encryption, and CloudKit schema behavior.
- Do not launch or operate Simulator; compile with generic Simulator destinations and leave real-device interaction checks to the user.
- Preserve all unrelated dirty-worktree changes and never add `Co-Authored-By` trailers.

---

## File Structure

- Create `privacy/AlbumMediaPaging.swift`: album scope, cursor, merge/load policies, SwiftData query construction, paging controller, and count snapshot.
- Modify `privacy/MainViews.swift`: own/reset paging state, route album rendering to paged items, refresh after mutations, persist album column count, and simplify media preview to one item.
- Modify `privacy/MediaGridViews.swift`: append-aware collection updates, two-screen load trigger, discrete column layout, and pinch-anchor restoration.
- Modify `privacy/VaultStore.swift`: expose cache clearing for lock/background memory safety while preserving the existing bounded thumbnail cache and async loader.
- Modify `privacyTests/privacyTests.swift`: deterministic policy and source-structure coverage for paging, zoom, append updates, and single-item preview.

---

### Task 1: Pure Paging and Column Policies

**Files:**
- Create: `privacy/AlbumMediaPaging.swift`
- Modify: `privacy/MediaGridViews.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Produces: `AlbumMediaKindFilter`, `AlbumMediaScope`, `AlbumMediaCursor`, `AlbumMediaPageMergePolicy`, `AlbumMediaLoadTriggerPolicy`.
- Produces: `MediaGridLayout.albumColumnCounts`, `defaultAlbumColumnCount`, `clampedAlbumColumnCount(_:)`, `settledAlbumColumnCount(startingColumnCount:gestureScale:)`, and `albumTileSize(for:columnCount:)`.
- Consumes: `VaultStore.innerVaultFolderId`, `VaultItemKind`, `CGFloat`, stable item IDs, and page-size inputs.

- [ ] **Step 1: Add failing policy tests**

Add tests that define the required paging and zoom contracts:

```swift
@Test func albumPageMergeAppendsOnlyNewStableIDs() {
    let merged = AlbumMediaPageMergePolicy.merge(existingIDs: ["a", "b"], incomingIDs: ["b", "c", "d"])
    #expect(merged == ["a", "b", "c", "d"])
}

@Test func albumLoadTriggerUsesTwoScreenWindow() {
    #expect(AlbumMediaLoadTriggerPolicy.shouldLoadMore(maxRequestedIndex: 160, loadedCount: 200, estimatedVisibleCount: 24))
    #expect(!AlbumMediaLoadTriggerPolicy.shouldLoadMore(maxRequestedIndex: 120, loadedCount: 200, estimatedVisibleCount: 24))
}

@Test func albumGridUsesOnlyApprovedColumnCounts() {
    #expect(MediaGridLayout.albumColumnCounts == [1, 3, 5, 7])
    #expect(MediaGridLayout.defaultAlbumColumnCount == 3)
    #expect(MediaGridLayout.settledAlbumColumnCount(startingColumnCount: 3, gestureScale: 2) == 1)
    #expect(MediaGridLayout.settledAlbumColumnCount(startingColumnCount: 3, gestureScale: 0.5) == 7)
}
```

- [ ] **Step 2: Compile tests and verify RED**

Run:

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/privacy-album-grid-dd build-for-testing
```

Expected: compilation fails because the new paging and discrete-column policies do not exist.

- [ ] **Step 3: Implement the policies**

Create these stable value types and pure functions:

```swift
enum AlbumMediaKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all, photos, videos
    var id: String { rawValue }
}

struct AlbumMediaScope: Equatable, Sendable {
    let isInnerVaultActive: Bool
    let filter: AlbumMediaKindFilter
    let favoritesOnly: Bool
}

struct AlbumMediaCursor: Equatable, Sendable {
    let createdAt: Date
    let id: String
}

enum AlbumMediaPageMergePolicy {
    static func merge(existingIDs: [String], incomingIDs: [String]) -> [String]
}

enum AlbumMediaLoadTriggerPolicy {
    static func shouldLoadMore(maxRequestedIndex: Int, loadedCount: Int, estimatedVisibleCount: Int) -> Bool
}
```

Add `[1, 3, 5, 7]` column constants and nearest-approved-column calculations to `MediaGridLayout`. Calculate tile width directly from collection width, spacing, and column count.

- [ ] **Step 4: Compile tests and verify GREEN compilation**

Run the Step 2 command. Expected: the policy tests compile with no errors.

- [ ] **Step 5: Commit the policy slice**

```bash
git add privacy/AlbumMediaPaging.swift privacy/MediaGridViews.swift privacyTests/privacyTests.swift
git commit -m "Add album paging and zoom policies"
```

### Task 2: SwiftData Album Paging Controller

**Files:**
- Modify: `privacy/AlbumMediaPaging.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: Task 1's `AlbumMediaScope`, `AlbumMediaCursor`, and merge policy.
- Produces: `@MainActor @Observable final class AlbumMediaPagingController` with `items`, `hasMore`, `isInitialLoading`, `isLoadingMore`, `error`, `loadFirstPage(scope:context:)`, `loadNextPageIfNeeded(context:)`, and `refreshPreservingLoadedRange(context:)`.
- Produces: `AlbumLibraryCountSnapshot` and `AlbumLibraryCountQuery.fetch(context:isInnerVaultActive:)` for category badges, favorite count, and free-limit count.

- [ ] **Step 1: Add failing paging-state tests**

Add deterministic tests for request gating and cursor progression without requiring UI:

```swift
@Test func albumPagingRequestPolicyRejectsDuplicateAndCompletedLoads() {
    #expect(AlbumMediaPagingRequestPolicy.canStart(isLoading: false, hasMore: true))
    #expect(!AlbumMediaPagingRequestPolicy.canStart(isLoading: true, hasMore: true))
    #expect(!AlbumMediaPagingRequestPolicy.canStart(isLoading: false, hasMore: false))
}

@Test func albumCursorUsesLastStableItem() {
    let date = Date(timeIntervalSince1970: 100)
    #expect(AlbumMediaCursorPolicy.cursor(createdAt: date, id: "z") == AlbumMediaCursor(createdAt: date, id: "z"))
}
```

- [ ] **Step 2: Compile and verify RED**

Run the Task 1 build-for-testing command. Expected: compilation fails for missing request and cursor policies.

- [ ] **Step 3: Implement page querying**

Use a `FetchDescriptor<VaultItem>` with a 201-item fetch limit, visual-kind predicate, current scope predicate, `createdAt` descending plus `id` ascending sort, and `(createdAt, id)` cursor boundary. Return the first 200 objects and use the extra object only to set `hasMore`.

The controller must:

```swift
@MainActor @Observable
final class AlbumMediaPagingController {
    private(set) var items: [VaultItem] = []
    private(set) var hasMore = true
    private(set) var isInitialLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?

    func loadFirstPage(scope: AlbumMediaScope, context: ModelContext) async
    func loadNextPageIfNeeded(context: ModelContext) async
    func refreshPreservingLoadedRange(context: ModelContext) async
}
```

Every reset increments a generation token. Apply fetched results only if the generation and scope still match. Merge by stable ID and never run two append fetches concurrently.

- [ ] **Step 4: Implement lightweight counts**

Add `fetchCount` descriptors that return album/audio/document/links/favorite/total active counts for the current vault space. Count queries must not decrypt metadata or materialize media objects.

- [ ] **Step 5: Compile tests and verify GREEN compilation**

Run the Task 1 build-for-testing command. Expected: success.

- [ ] **Step 6: Commit the paging controller**

```bash
git add privacy/AlbumMediaPaging.swift privacyTests/privacyTests.swift
git commit -m "Implement paged album data source"
```

### Task 3: Incremental UICollectionView Loading

**Files:**
- Modify: `privacy/MediaGridViews.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: loaded `items`, Task 1's load-trigger policy, current column count, and async `loadMoreAction`.
- Produces: `AlbumGridUpdatePlan.append(Range<Int>)`, append-only collection inserts, dynamic two-screen threshold, and footer loading/retry state callbacks.

- [ ] **Step 1: Add failing append-plan tests**

```swift
@Test @MainActor func albumGridUsesInsertPlanForAppendedPage() {
    let previous = [AlbumGridItemRenderState.stub(id: "a"), AlbumGridItemRenderState.stub(id: "b")]
    let next = previous + [AlbumGridItemRenderState.stub(id: "c")]
    #expect(AlbumGridUpdatePolicy.plan(previous: previous, next: next) == .append(2..<3))
}
```

Keep the existing expectations that reordering or removal returns `.reloadAll` and visible state-only changes return `.reconfigure`.

- [ ] **Step 2: Compile and verify RED**

Run the Task 1 build-for-testing command. Expected: compilation fails because `.append` does not exist.

- [ ] **Step 3: Add append-only collection updates**

Extend the update policy so a strict previous-ID prefix produces `.append(previous.count..<next.count)`. In `reloadDataIfNeeded`, set the new render state before `performBatchUpdates`, insert the new index paths, and fall back to `reloadData()` only for non-append structural changes.

- [ ] **Step 4: Trigger page loading before the tail**

Add `loadMoreAction: () -> Void` to `AlbumZoomableMediaGrid`. Call it from `prefetchItemsAt` and `willDisplay` when the maximum requested index enters a two-screen window derived from bounds height, tile height, and current column count. The paging controller remains responsible for duplicate-request suppression.

- [ ] **Step 5: Preserve thumbnail cancellation**

Keep one tokenized prefetch task per item ID, cancel it in `cancelPrefetchingForItemsAt`, and do not start video playback or original-file decryption from a grid callback.

- [ ] **Step 6: Compile and verify GREEN compilation**

Run the Task 1 build-for-testing command. Expected: success.

- [ ] **Step 7: Commit incremental loading**

```bash
git add privacy/MediaGridViews.swift privacyTests/privacyTests.swift
git commit -m "Load album pages during scrolling"
```

### Task 4: Anchored 1/3/5/7 Pinch Zoom

**Files:**
- Modify: `privacy/MediaGridViews.swift`
- Modify: `privacy/MainViews.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: Task 1's discrete-column policy and current collection-view item IDs.
- Produces: `@Binding var columnCount: Int`, gesture anchor capture, offset restoration, and `@AppStorage("vault.mediaGridColumns.album")` persistence.

- [ ] **Step 1: Add failing anchor-policy tests**

```swift
@Test func albumZoomAnchorRestoresViewportOffset() {
    let offset = AlbumGridZoomAnchorPolicy.contentOffset(
        itemCenterY: 900,
        viewportAnchorY: 300,
        minimumOffsetY: 0,
        maximumOffsetY: 1400
    )
    #expect(offset == 600)
    #expect(AlbumGridZoomAnchorPolicy.contentOffset(itemCenterY: 50, viewportAnchorY: 300, minimumOffsetY: 0, maximumOffsetY: 1400) == 0)
}
```

- [ ] **Step 2: Compile and verify RED**

Run the Task 1 build-for-testing command. Expected: compilation fails for the missing anchor policy.

- [ ] **Step 3: Convert the album binding to column count**

Replace the album's arbitrary scale binding with an integer column binding. Keep scale-based behavior for audio and document grids. Persist the album value under `vault.mediaGridColumns.album`, clamp stored legacy/invalid values to the nearest supported count, and use 3 when absent.

- [ ] **Step 4: Capture and restore the pinch anchor**

On pinch begin, record the nearest visible item ID and the gesture center's viewport Y. During changes, apply lightweight transforms only to visible cells. On end, settle to the nearest approved count, invalidate layout once, locate the same item by stable ID, and set clamped `contentOffset.y = itemCenterY - viewportAnchorY`.

- [ ] **Step 5: Preserve page and scroll state**

Do not recreate the collection view on column changes or page appends. Clear visible transforms on completion/cancellation and schedule thumbnail prefetch again at the new tile size.

- [ ] **Step 6: Compile and verify GREEN compilation**

Run the Task 1 build-for-testing command. Expected: success.

- [ ] **Step 7: Commit anchored zoom**

```bash
git add privacy/MainViews.swift privacy/MediaGridViews.swift privacyTests/privacyTests.swift
git commit -m "Add anchored album pinch zoom"
```

### Task 5: Wire Paged Album State Into Vault Home

**Files:**
- Modify: `privacy/MainViews.swift`
- Modify: `privacy/AlbumMediaPaging.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `AlbumMediaPagingController`, `AlbumLibraryCountSnapshot`, existing `AlbumMediaFilter`, Mo Layer state, and grid `loadMoreAction`.
- Produces: paged `visibleItems` for `.album`, nonvisual-only retained query data for other categories, scope reset tasks, mutation refresh, and accurate lightweight counts.

- [ ] **Step 1: Add failing source-structure assertions**

Add a test that reads `MainViews.swift` and requires `AlbumMediaPagingController`, `loadNextPageIfNeeded`, and `AlbumLibraryCountSnapshot`, while rejecting the unfiltered declaration:

```swift
@Query(sort: \VaultItem.createdAt, order: .reverse) private var items: [VaultItem]
```

- [ ] **Step 2: Compile and verify RED**

Run the Task 1 build-for-testing command. Expected: the source assertion is present but the implementation contract is not satisfied at runtime; compilation also fails until the new home properties are connected.

- [ ] **Step 3: Narrow retained queries and route album items**

Replace the unfiltered `@Query` with a query that excludes `image`, `livePhoto`, and `video`. For `.album`, `visibleItems` returns `albumPaging.items`; for other categories it filters the retained nonvisual items exactly as before.

- [ ] **Step 4: Load scopes and counts**

Create an `AlbumMediaScope` from `isInnerVaultActive`, `albumMediaFilter`, and `showsFavoriteAlbumItemsOnly`. Use `.task(id:)` to load the first page when that scope changes. Refresh count snapshots on appear and after imports, cloud refresh, delete, move, favorite changes, and preview dismissal.

- [ ] **Step 5: Preserve current actions**

Bulk selection operates on currently loaded visible items. Category badges and free-import limits use count snapshots, not loaded-page length. Mo Layer logging uses count snapshots instead of reducing an all-item array.

- [ ] **Step 6: Connect grid loading and states**

Pass `albumPaging.items`, the integer column binding, and `loadMoreAction` into `AlbumZoomableMediaGrid`. Keep existing visible-item repair, selection, favorite, and thumbnail closures.

- [ ] **Step 7: Compile and verify GREEN compilation**

Run the Task 1 build-for-testing command. Expected: success.

- [ ] **Step 8: Commit home integration**

```bash
git add privacy/MainViews.swift privacy/AlbumMediaPaging.swift privacyTests/privacyTests.swift
git commit -m "Integrate paged album into vault home"
```

### Task 6: Single-Item Media Preview and Resource Cleanup

**Files:**
- Modify: `privacy/MainViews.swift`
- Modify: `privacy/VaultStore.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: one selected `VaultItem`, existing `FullscreenMediaPage`, image/live-photo loaders, and video player view.
- Produces: `MediaPreviewSelection(item:)`, `VaultMediaPreviewView(item:isInnerVaultActive:)`, single-item delete/move dismissal, and `VaultStore.clearDecryptedMediaCaches()`.

- [ ] **Step 1: Add failing single-preview assertions**

Add source checks requiring `let item: VaultItem` in `MediaPreviewSelection` and rejecting `.scrollTargetBehavior(.paging)`, `LazyHStack`, `previewItems`, `scrollPosition`, and adjacent-item selection inside `VaultMediaPreviewView`.

- [ ] **Step 2: Compile and verify RED**

Run the Task 1 build-for-testing command. Expected: assertions describe behavior not yet implemented.

- [ ] **Step 3: Simplify selection and presentation**

Change every preview caller to pass only the selected item. Render one `FullscreenMediaPage(item:loadMode:.selected,livePhotoPlaybackTrigger:)` full-screen without a horizontal scroll view. Keep close, favorite, details, export, save, move, delete, and Live Photo controls.

- [ ] **Step 4: Dismiss after destructive scope changes**

After successful delete or move to Mo Layer, dismiss the single preview immediately. The home cover's dismissal refresh restores the grid around its existing visible anchor.

- [ ] **Step 5: Clear decrypted media resources**

Expose a VaultStore cache-clear method that removes thumbnail/metadata cache entries and cancels thumbnail prefetch work when the app locks or receives a memory warning. Preserve the existing player view's `onDisappear` pause and observer cleanup.

- [ ] **Step 6: Compile and verify GREEN compilation**

Run the Task 1 build-for-testing command. Expected: success.

- [ ] **Step 7: Commit single-item preview**

```bash
git add privacy/MainViews.swift privacy/VaultStore.swift privacyTests/privacyTests.swift
git commit -m "Replace media pager with single preview"
```

### Task 7: Verification and Handoff

**Files:**
- Modify only if verification exposes a defect in the files above.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: build evidence and a real-device verification checklist.

- [ ] **Step 1: Compile the app**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/privacy-album-grid-dd build
```

Expected: `** BUILD SUCCEEDED **` with no new compiler errors.

- [ ] **Step 2: Compile the unit-test bundle**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/privacy-album-grid-dd build-for-testing
```

Expected: `** TEST BUILD SUCCEEDED **`. This compiles tests without launching Simulator.

- [ ] **Step 3: Review the exact diff**

```bash
git diff --check
git diff --stat -- privacy/AlbumMediaPaging.swift privacy/MainViews.swift privacy/MediaGridViews.swift privacy/VaultStore.swift privacyTests/privacyTests.swift
```

Expected: no whitespace errors and no unrelated files in the feature diff.

- [ ] **Step 4: Provide real-device checks**

Ask the user to verify a large library on an iPhone: fast vertical scrolling through several page boundaries, repeated 1/3/5/7 pinch changes at mid-list, filter and Mo Layer resets, opening/closing photos and videos, and returning to the same grid position. If a real-device hitch remains, capture Time Profiler, Hangs, and Animation Hitches rather than judging from Simulator.

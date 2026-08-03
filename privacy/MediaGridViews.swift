import SwiftUI
import UIKit
import OSLog

enum MediaGridLayout {
    static let defaultScale: CGFloat = 1
    static let minimumScale: CGFloat = 0.16
    static let maximumScale: CGFloat = 3.25
    static let baseTileMinimum: CGFloat = 108
    static let minimumTileSize: CGFloat = 24
    static let interactionMinHeight: CGFloat = 560
    static let albumViewportScreenRatio: CGFloat = 0.72
    static let spacing: CGFloat = 6
    static let coordinateSpaceName = "vault.mediaGrid"
    static let liveZoomAnimation: Animation = .smooth(duration: 0.16, extraBounce: 0.02)
    static let settledZoomAnimation: Animation = .interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.08)

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func tileMinimum(for containerWidth: CGFloat, scale: CGFloat) -> CGFloat {
        let width = max(containerWidth, minimumTileSize)
        let scaledTile = round(baseTileMinimum * clampedScale(scale))
        return min(max(scaledTile, minimumTileSize), width)
    }

    static func columnCount(for containerWidth: CGFloat, scale: CGFloat) -> Int {
        let tile = tileMinimum(for: containerWidth, scale: scale)
        let availableWidth = max(containerWidth + spacing, tile)
        return max(1, Int(floor(availableWidth / (tile + spacing))))
    }

    static func tileInteractionScale(effectiveScale: CGFloat, committedScale: CGFloat) -> CGFloat {
        let baseScale = max(clampedScale(committedScale), 0.001)
        let ratio = clampedScale(effectiveScale) / baseScale
        return min(max(1 + (ratio - 1) * 0.14, 0.88), 1.14)
    }

    static func zoomLift(effectiveScale: CGFloat, committedScale: CGFloat) -> CGFloat {
        let baseScale = max(clampedScale(committedScale), 0.001)
        let distance = abs(clampedScale(effectiveScale) / baseScale - 1)
        return min(distance * 2.4, 1)
    }

    static func shadowRadius(lift: CGFloat) -> CGFloat {
        1 + lift * 13
    }

    static func shadowOpacity(lift: CGFloat) -> Double {
        Double(0.04 + lift * 0.18)
    }

    static func snappedScale(_ proposedScale: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let proposed = clampedScale(proposedScale)
        let columns = columnCount(for: containerWidth, scale: proposed)
        let availableWidth = max(containerWidth - spacing * CGFloat(max(columns - 1, 0)), minimumTileSize)
        let snappedTile = max(floor(availableWidth / CGFloat(columns)), minimumTileSize)
        return clampedScale(snappedTile / baseTileMinimum)
    }

    static func persistedScale(_ value: Double) -> CGFloat {
        clampedScale(CGFloat(value))
    }

    static func storedScale(_ value: CGFloat) -> Double {
        Double(clampedScale(value))
    }

    static func layoutScale(
        committedScale: CGFloat,
        proposedScale: CGFloat,
        isPinching: Bool
    ) -> CGFloat {
        clampedScale(isPinching ? committedScale : proposedScale)
    }

    static func albumViewportHeight(for screenHeight: CGFloat = UIScreen.main.bounds.height) -> CGFloat {
        max(interactionMinHeight, floor(screenHeight * albumViewportScreenRatio))
    }
}

enum MediaGridScaleStorage {
    static let albumKey = "vault.mediaGridScale.album"
    static let audioKey = "vault.mediaGridScale.audio"
    static let documentsKey = "vault.mediaGridScale.documents"

    static let defaultStoredScale = Double(MediaGridLayout.defaultScale)
}

struct AlbumGridItemRenderState: Equatable {
    let id: String
    let thumbnailIdentity: String
    let statusIdentity: String
    let isSelected: Bool
    let isSelectionMode: Bool

    init(
        id: String,
        thumbnailIdentity: String,
        statusIdentity: String,
        isSelected: Bool,
        isSelectionMode: Bool = false
    ) {
        self.id = id
        self.thumbnailIdentity = thumbnailIdentity
        self.statusIdentity = statusIdentity
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
    }
}

enum AlbumGridUpdatePlan: Equatable {
    case none
    case reloadAll
    case reconfigure([Int])
}

enum AlbumGridUpdatePolicy {
    static func plan(
        previous: [AlbumGridItemRenderState]?,
        next: [AlbumGridItemRenderState]
    ) -> AlbumGridUpdatePlan {
        guard let previous else { return .reloadAll }
        guard previous.map(\.id) == next.map(\.id) else { return .reloadAll }
        let changedIndices = next.indices.filter { previous[$0] != next[$0] }
        return changedIndices.isEmpty ? .none : .reconfigure(changedIndices)
    }
}

enum AlbumVideoDurationFormatter {
    static func text(for seconds: Double, compact: Bool = false) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if compact {
            if hours > 0 { return "\(hours)h" }
            if minutes > 0 { return "\(minutes)m" }
            return "1m"
        }

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        }
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }
}

private let mediaGridPerformanceLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy",
    category: "MediaGridPerformance"
)

struct ZoomableMediaGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable, Data.Element.ID: Hashable {
    let items: Data
    @Binding var scale: CGFloat
    let content: (Data.Element) -> Content

    @GestureState private var pinchScale: CGFloat = 1
    @State private var containerWidth: CGFloat = 360
    @State private var isPinching = false
    @Namespace private var zoomNamespace

    init(
        items: Data,
        scale: Binding<CGFloat>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self._scale = scale
        self.content = content
    }

    var body: some View {
        let effectiveScale = MediaGridLayout.clampedScale(scale * pinchScale)
        let layoutScale = isPinching ? scale : effectiveScale
        let columnCount = MediaGridLayout.columnCount(for: containerWidth, scale: layoutScale)
        let columns = Array(
            repeating: GridItem(.flexible(minimum: MediaGridLayout.minimumTileSize), spacing: MediaGridLayout.spacing),
            count: columnCount
        )
        let interactionScale = MediaGridLayout.tileInteractionScale(
            effectiveScale: effectiveScale,
            committedScale: scale
        )
        let lift = isPinching ? MediaGridLayout.zoomLift(effectiveScale: effectiveScale, committedScale: scale) : 0

        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: MediaGridLayout.interactionMinHeight)

            LazyVGrid(columns: columns, spacing: MediaGridLayout.spacing) {
                ForEach(items) { item in
                    content(item)
                        .matchedGeometryEffect(id: item.id, in: zoomNamespace)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: MediaGridItemFramePreferenceKey.self,
                                    value: [AnyHashable(item.id): proxy.frame(in: .named(MediaGridLayout.coordinateSpaceName))]
                                )
                            }
                        )
                        .scaleEffect(interactionScale)
                        .shadow(
                            color: .black.opacity(MediaGridLayout.shadowOpacity(lift: lift)),
                            radius: MediaGridLayout.shadowRadius(lift: lift),
                            x: 0,
                            y: 2 + lift * 8
                        )
                        .zIndex(isPinching ? 1 : 0)
                        .animation(MediaGridLayout.liveZoomAnimation, value: interactionScale)
                        .animation(MediaGridLayout.liveZoomAnimation, value: lift)
                }
            }
        }
        .coordinateSpace(name: MediaGridLayout.coordinateSpaceName)
        .frame(maxWidth: .infinity, minHeight: MediaGridLayout.interactionMinHeight, alignment: .top)
        .contentShape(Rectangle())
        .animation(MediaGridLayout.settledZoomAnimation, value: columnCount)
        .animation(MediaGridLayout.settledZoomAnimation, value: scale)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MediaGridWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MediaGridWidthPreferenceKey.self) { width in
            if width > 0 {
                containerWidth = width
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { _ in
                    if !isPinching {
                        isPinching = true
                    }
                }
                .updating($pinchScale) { value, state, transaction in
                    transaction.animation = MediaGridLayout.liveZoomAnimation
                    state = value
                }
                .onEnded { value in
                    let targetScale = MediaGridLayout.snappedScale(scale * value, containerWidth: containerWidth)
                    withAnimation(MediaGridLayout.settledZoomAnimation) {
                        scale = targetScale
                    }
                    isPinching = false
                }
        )
    }
}

struct AlbumZoomableMediaGrid: UIViewRepresentable {
    let items: [VaultItem]
    @Binding var scale: CGFloat
    @Binding var contentHeight: CGFloat
    let isSelectionMode: Bool
    let selectedItemIds: Set<String>
    let cachedThumbnailProvider: (VaultItem) -> UIImage?
    let videoDurationProvider: (VaultItem) -> Double?
    let thumbnailProvider: @MainActor (VaultItem) async -> UIImage?
    let visibleItemIDsDidChange: (Set<String>) -> Void
    let openAction: (VaultItem) -> Void
    let toggleSelectionAction: (VaultItem) -> Void
    let enterSelectionAction: (VaultItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = MediaGridLayout.spacing
        layout.minimumLineSpacing = MediaGridLayout.spacing
        layout.sectionInset = .zero

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.isScrollEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.allowsSelection = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(AlbumMediaCollectionCell.self, forCellWithReuseIdentifier: AlbumMediaCollectionCell.reuseIdentifier)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        collectionView.addGestureRecognizer(pinch)
        context.coordinator.pinchRecognizer = pinch

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 18
        longPress.delegate = context.coordinator
        collectionView.addGestureRecognizer(longPress)

        let selectionPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSelectionPan(_:)))
        selectionPan.minimumNumberOfTouches = 1
        selectionPan.maximumNumberOfTouches = 1
        selectionPan.delegate = context.coordinator
        collectionView.addGestureRecognizer(selectionPan)
        context.coordinator.selectionPanRecognizer = selectionPan

        context.coordinator.collectionView = collectionView
        context.coordinator.applyLayout(animated: false)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyLayout(animated: false)
        context.coordinator.reloadDataIfNeeded(collectionView)
        context.coordinator.updateContentHeight()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        var parent: AlbumZoomableMediaGrid
        weak var collectionView: UICollectionView?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var selectionPanRecognizer: UIPanGestureRecognizer?
        private var pinchStartScale: CGFloat = MediaGridLayout.defaultScale
        private var transientScale: CGFloat?
        private var isPinching = false
        private var selectedDuringPan = Set<String>()
        private var selectedDuringLongPress = Set<String>()
        private var visibleItemIDs = Set<String>()
        private var pendingVisibleItemsReport: DispatchWorkItem?
        private var contentHeightUpdateScheduled = false
        private var renderedItems: [AlbumGridItemRenderState]?

        init(_ parent: AlbumZoomableMediaGrid) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AlbumMediaCollectionCell.reuseIdentifier,
                for: indexPath
            ) as? AlbumMediaCollectionCell else {
                return UICollectionViewCell()
            }
            let item = parent.items[indexPath.item]
            let thumbnailProvider = parent.thumbnailProvider
            cell.configure(
                item: item,
                thumbnail: parent.cachedThumbnailProvider(item),
                videoDuration: parent.videoDurationProvider(item),
                thumbnailProvider: { await thumbnailProvider(item) },
                isSelectionMode: parent.isSelectionMode,
                isSelected: parent.selectedItemIds.contains(item.id)
            )
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard parent.items.indices.contains(indexPath.item) else { return }
            visibleItemIDs.insert(parent.items[indexPath.item].id)
            scheduleVisibleItemsReport()
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didEndDisplaying cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard let mediaCell = cell as? AlbumMediaCollectionCell,
                  let itemID = mediaCell.representedItemID else {
                return
            }
            visibleItemIDs.remove(itemID)
            scheduleVisibleItemsReport()
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard !isPinching else { return }
            let item = parent.items[indexPath.item]
            if parent.isSelectionMode {
                parent.toggleSelectionAction(item)
            } else {
                parent.openAction(item)
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let collectionView else { return }
            switch recognizer.state {
            case .began:
                isPinching = true
                pinchStartScale = parent.scale
                transientScale = parent.scale
            case .changed:
                transientScale = MediaGridLayout.clampedScale(pinchStartScale * recognizer.scale)
                applyInteractiveCellScale()
            case .ended, .cancelled, .failed:
                let proposedScale = transientScale ?? parent.scale
                let snapped = MediaGridLayout.snappedScale(proposedScale, containerWidth: collectionView.bounds.width)
                transientScale = snapped
                isPinching = false
                let startedAt = CFAbsoluteTimeGetCurrent()
                UIView.animate(
                    withDuration: 0.24,
                    delay: 0,
                    usingSpringWithDamping: 0.86,
                    initialSpringVelocity: 0.2,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    self.clearInteractiveCellScale()
                    self.applyLayout(animated: false)
                    collectionView.layoutIfNeeded()
                } completion: { _ in
                    self.parent.scale = snapped
                    self.transientScale = nil
                    self.applyLayout(animated: false)
                    self.updateContentHeight()
                    let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                    if elapsedMs > 16 {
                        mediaGridPerformanceLogger.info("Album pinch settled scale=\(snapped, privacy: .public) itemCount=\(self.parent.items.count, privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
                    }
                }
            default:
                break
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            let location = recognizer.location(in: collectionView)
            switch recognizer.state {
            case .began:
                selectedDuringLongPress.removeAll()
                guard let item = item(at: location, in: collectionView), item.kind.isVisualMedia else { return }
                selectedDuringLongPress.insert(item.id)
                parent.enterSelectionAction(item)
            case .changed:
                guard parent.isSelectionMode, let item = item(at: location, in: collectionView), item.kind.isVisualMedia else { return }
                selectOnce(item, tracking: &selectedDuringLongPress)
            case .ended, .cancelled, .failed:
                selectedDuringLongPress.removeAll()
            default:
                break
            }
        }

        @objc func handleSelectionPan(_ recognizer: UIPanGestureRecognizer) {
            guard parent.isSelectionMode, let collectionView else { return }
            let location = recognizer.location(in: collectionView)
            switch recognizer.state {
            case .began:
                selectedDuringPan.removeAll()
                if let item = item(at: location, in: collectionView), item.kind.isVisualMedia {
                    selectOnce(item, tracking: &selectedDuringPan)
                }
            case .changed:
                if let item = item(at: location, in: collectionView), item.kind.isVisualMedia {
                    selectOnce(item, tracking: &selectedDuringPan)
                }
            case .ended, .cancelled, .failed:
                selectedDuringPan.removeAll()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === pinchRecognizer || otherGestureRecognizer === pinchRecognizer || parent.isSelectionMode
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === selectionPanRecognizer {
                return parent.isSelectionMode
            }
            return true
        }

        func reloadDataIfNeeded(_ collectionView: UICollectionView) {
            let nextItems = makeRenderState()
            let plan = AlbumGridUpdatePolicy.plan(previous: renderedItems, next: nextItems)
            guard plan != .none else { return }
            let startedAt = CFAbsoluteTimeGetCurrent()
            let reason: String
            switch plan {
            case .none:
                return
            case .reloadAll:
                reason = renderedItems == nil ? "initial" : "structure"
                visibleItemIDs.removeAll(keepingCapacity: true)
                collectionView.reloadData()
                scheduleVisibleItemsReport()
            case let .reconfigure(changedIndices):
                reason = "visible-items"
                let changedIndexSet = Set(changedIndices)
                let visibleChanges = collectionView.indexPathsForVisibleItems.filter {
                    changedIndexSet.contains($0.item)
                }
                if !visibleChanges.isEmpty {
                    collectionView.reconfigureItems(at: visibleChanges)
                }
            }
            renderedItems = nextItems
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if elapsedMs > 16 {
                mediaGridPerformanceLogger.info("Album grid update reason=\(reason, privacy: .public) itemCount=\(self.parent.items.count, privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
            }
        }

        func applyLayout(animated: Bool) {
            guard let collectionView,
                  let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
                return
            }
            let width = max(collectionView.bounds.width, MediaGridLayout.minimumTileSize)
            let tile = MediaGridLayout.tileMinimum(for: width, scale: currentLayoutScale)
            let tileSize = CGSize(width: tile, height: tile)
            guard abs(layout.itemSize.width - tileSize.width) > 0.5 || abs(layout.itemSize.height - tileSize.height) > 0.5 else {
                return
            }
            let startedAt = CFAbsoluteTimeGetCurrent()
            let update = {
                layout.itemSize = tileSize
                layout.invalidateLayout()
            }
            if animated {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: update) { _ in
                    self.updateContentHeight()
                    self.logLayoutIfSlow(startedAt: startedAt, tile: tile)
                }
            } else {
                update()
                updateContentHeight()
                logLayoutIfSlow(startedAt: startedAt, tile: tile)
            }
        }

        func updateContentHeight() {
            guard let collectionView, !contentHeightUpdateScheduled else { return }
            contentHeightUpdateScheduled = true
            DispatchQueue.main.async {
                self.contentHeightUpdateScheduled = false
                collectionView.layoutIfNeeded()
                let height = collectionView.collectionViewLayout.collectionViewContentSize.height
                guard height.isFinite, height >= 0 else { return }
                let viewportHeight = MediaGridLayout.albumViewportHeight()
                let nextHeight = min(max(1, ceil(height)), viewportHeight)
                if abs(self.parent.contentHeight - nextHeight) > 0.5 {
                    self.parent.contentHeight = nextHeight
                }
            }
        }

        private var currentLayoutScale: CGFloat {
            MediaGridLayout.layoutScale(
                committedScale: parent.scale,
                proposedScale: transientScale ?? parent.scale,
                isPinching: isPinching
            )
        }

        private func applyInteractiveCellScale() {
            let proposedScale = transientScale ?? parent.scale
            let visualScale = MediaGridLayout.tileInteractionScale(
                effectiveScale: proposedScale,
                committedScale: parent.scale
            )
            for cell in collectionView?.visibleCells ?? [] {
                cell.transform = CGAffineTransform(scaleX: visualScale, y: visualScale)
            }
        }

        private func clearInteractiveCellScale() {
            for cell in collectionView?.visibleCells ?? [] {
                cell.transform = .identity
            }
        }

        private func scheduleVisibleItemsReport() {
            pendingVisibleItemsReport?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.parent.visibleItemIDsDidChange(self.visibleItemIDs)
            }
            pendingVisibleItemsReport = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }

        private func makeRenderState() -> [AlbumGridItemRenderState] {
            parent.items.map { item in
                AlbumGridItemRenderState(
                    id: item.id,
                    thumbnailIdentity: item.encryptedThumbPath ?? "",
                    statusIdentity: "\(item.kind.rawValue)|\(item.syncStatusRawValue)|\(item.assetStateRawValue)|\(item.updatedAt.timeIntervalSince1970)",
                    isSelected: parent.selectedItemIds.contains(item.id),
                    isSelectionMode: parent.isSelectionMode
                )
            }
        }

        private func logLayoutIfSlow(startedAt: CFAbsoluteTime, tile: CGFloat) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if elapsedMs > 8 {
                mediaGridPerformanceLogger.debug("Album grid layout tile=\(tile, privacy: .public) itemCount=\(self.parent.items.count, privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
            }
        }

        private func item(at location: CGPoint, in collectionView: UICollectionView) -> VaultItem? {
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  parent.items.indices.contains(indexPath.item) else {
                return nil
            }
            return parent.items[indexPath.item]
        }

        private func selectOnce(_ item: VaultItem, tracking selectedIds: inout Set<String>) {
            guard !selectedIds.contains(item.id) else { return }
            selectedIds.insert(item.id)
            if !parent.selectedItemIds.contains(item.id) {
                parent.toggleSelectionAction(item)
            }
        }
    }
}

private final class AlbumMediaCollectionCell: UICollectionViewCell {
    static let reuseIdentifier = "AlbumMediaCollectionCell"

    private let imageView = UIImageView()
    private let placeholderIcon = UIImageView()
    private let placeholderLabel = UILabel()
    private let gradientLayer = CAGradientLayer()
    private let mediaBadgeBackground = UIView()
    private let mediaBadge = UIImageView()
    private let durationLabel = UILabel()
    private let syncDot = UIView()
    private let selectionCircle = UIImageView()
    private let selectionBorder = CAShapeLayer()
    private var mediaBadgeWidthConstraint: NSLayoutConstraint?
    private var selectionCircleTopConstraint: NSLayoutConstraint?
    private var selectionCircleLeadingConstraint: NSLayoutConstraint?
    private var selectionCircleWidthConstraint: NSLayoutConstraint?
    private var selectionCircleHeightConstraint: NSLayoutConstraint?
    private var isCurrentlySelected = false
    private var thumbnailTask: Task<Void, Never>?
    private(set) var representedItemID: String?
    private var representedThumbnailIdentity: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.tintColor = .systemTeal
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = .preferredFont(forTextStyle: .caption2)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        mediaBadge.tintColor = .white
        mediaBadge.contentMode = .center
        mediaBadge.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .left
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        mediaBadgeBackground.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        mediaBadgeBackground.translatesAutoresizingMaskIntoConstraints = false

        syncDot.translatesAutoresizingMaskIntoConstraints = false

        selectionCircle.tintColor = .systemBlue
        selectionCircle.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        selectionCircle.layer.cornerRadius = 12
        selectionCircle.translatesAutoresizingMaskIntoConstraints = false

        contentView.layer.addSublayer(gradientLayer)
        contentView.layer.addSublayer(selectionBorder)
        contentView.addSubview(imageView)
        contentView.addSubview(placeholderIcon)
        contentView.addSubview(placeholderLabel)
        contentView.addSubview(mediaBadgeBackground)
        mediaBadgeBackground.addSubview(mediaBadge)
        mediaBadgeBackground.addSubview(durationLabel)
        contentView.addSubview(syncDot)
        contentView.addSubview(selectionCircle)

        let selectionCircleTopConstraint = selectionCircle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6)
        let selectionCircleLeadingConstraint = selectionCircle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6)
        let selectionCircleWidthConstraint = selectionCircle.widthAnchor.constraint(equalToConstant: 24)
        let selectionCircleHeightConstraint = selectionCircle.heightAnchor.constraint(equalToConstant: 24)
        self.selectionCircleTopConstraint = selectionCircleTopConstraint
        self.selectionCircleLeadingConstraint = selectionCircleLeadingConstraint
        self.selectionCircleWidthConstraint = selectionCircleWidthConstraint
        self.selectionCircleHeightConstraint = selectionCircleHeightConstraint
        let mediaBadgeWidthConstraint = mediaBadgeBackground.widthAnchor.constraint(equalToConstant: 28)
        self.mediaBadgeWidthConstraint = mediaBadgeWidthConstraint

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -6),
            placeholderIcon.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.28),
            placeholderIcon.heightAnchor.constraint(equalTo: placeholderIcon.widthAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: placeholderIcon.bottomAnchor, constant: 4),
            placeholderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            placeholderLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            mediaBadgeBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            mediaBadgeBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            mediaBadgeWidthConstraint,
            mediaBadgeBackground.heightAnchor.constraint(equalToConstant: 28),

            mediaBadge.leadingAnchor.constraint(equalTo: mediaBadgeBackground.leadingAnchor),
            mediaBadge.centerYAnchor.constraint(equalTo: mediaBadgeBackground.centerYAnchor),
            mediaBadge.widthAnchor.constraint(equalToConstant: 28),
            mediaBadge.heightAnchor.constraint(equalTo: mediaBadgeBackground.heightAnchor),

            durationLabel.leadingAnchor.constraint(equalTo: mediaBadge.trailingAnchor, constant: -1),
            durationLabel.trailingAnchor.constraint(equalTo: mediaBadgeBackground.trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: mediaBadgeBackground.centerYAnchor),

            syncDot.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            syncDot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            syncDot.widthAnchor.constraint(equalToConstant: 7),
            syncDot.heightAnchor.constraint(equalToConstant: 7),

            selectionCircleTopConstraint,
            selectionCircleLeadingConstraint,
            selectionCircleWidthConstraint,
            selectionCircleHeightConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cornerRadius = min(max(bounds.width * 0.08, 5), 8)
        contentView.layer.cornerRadius = cornerRadius
        imageView.layer.cornerRadius = cornerRadius
        gradientLayer.frame = contentView.bounds
        gradientLayer.cornerRadius = cornerRadius
        selectionBorder.frame = contentView.bounds
        selectionBorder.path = UIBezierPath(roundedRect: contentView.bounds, cornerRadius: cornerRadius).cgPath
        mediaBadgeBackground.layer.cornerRadius = mediaBadgeBackground.bounds.height / 2
        syncDot.layer.cornerRadius = syncDot.bounds.width / 2
        updateSelectionMetrics()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        representedItemID = nil
        representedThumbnailIdentity = nil
        imageView.image = nil
        placeholderIcon.image = nil
        placeholderLabel.text = nil
        mediaBadgeBackground.isHidden = true
        mediaBadge.image = nil
        durationLabel.text = nil
        durationLabel.isHidden = true
        mediaBadgeWidthConstraint?.constant = 28
        mediaBadgeBackground.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        selectionCircle.image = nil
        selectionCircle.isHidden = true
        selectionBorder.strokeColor = UIColor.clear.cgColor
    }

    func configure(
        item: VaultItem,
        thumbnail: UIImage?,
        videoDuration: Double?,
        thumbnailProvider: @escaping @MainActor () async -> UIImage?,
        isSelectionMode: Bool,
        isSelected: Bool
    ) {
        let thumbnailIdentity = item.encryptedThumbPath ?? ""
        let itemChanged = representedItemID != item.id
        let thumbnailChanged = representedThumbnailIdentity != thumbnailIdentity
        if itemChanged || thumbnailChanged {
            thumbnailTask?.cancel()
            thumbnailTask = nil
        }
        representedItemID = item.id
        representedThumbnailIdentity = thumbnailIdentity

        if let thumbnail {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            showThumbnail(thumbnail)
        } else {
            showPlaceholder(for: item.kind)
            if thumbnailTask == nil {
                let itemID = item.id
                thumbnailTask = Task { @MainActor [weak self] in
                    let loadedThumbnail = await thumbnailProvider()
                    guard !Task.isCancelled,
                          let self,
                          self.representedItemID == itemID else {
                        return
                    }
                    self.thumbnailTask = nil
                    if let loadedThumbnail {
                        self.showThumbnail(loadedThumbnail)
                    }
                }
            }
        }

        configureGradient(for: item.kind)
        configureMediaBadge(for: item.kind, videoDuration: videoDuration)
        syncDot.backgroundColor = syncDotColor(for: item.syncStatus)
        configureSelection(isSelectionMode: isSelectionMode, isSelected: isSelected)
    }

    private func showThumbnail(_ thumbnail: UIImage) {
        imageView.image = thumbnail
        imageView.isHidden = false
        placeholderIcon.isHidden = true
        placeholderLabel.isHidden = true
    }

    private func showPlaceholder(for kind: VaultItemKind) {
        imageView.image = nil
        imageView.isHidden = true
        placeholderIcon.isHidden = false
        placeholderLabel.isHidden = bounds.width < 72
        placeholderIcon.image = UIImage(systemName: iconName(for: kind))
        placeholderLabel.text = kind.rawValue.uppercased()
    }

    private func configureGradient(for kind: VaultItemKind) {
        guard kind.isVisualMedia else {
            gradientLayer.colors = []
            return
        }
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(kind == .video ? 0.34 : 0.18).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func configureMediaBadge(for kind: VaultItemKind, videoDuration: Double?) {
        switch kind {
        case .video:
            mediaBadge.image = UIImage(systemName: "play.fill")
            mediaBadgeBackground.isHidden = false
            mediaBadgeBackground.backgroundColor = UIColor.black.withAlphaComponent(0.38)
            if let videoDuration {
                durationLabel.text = AlbumVideoDurationFormatter.text(for: videoDuration, compact: bounds.width < 62)
                durationLabel.isHidden = false
                mediaBadgeWidthConstraint?.constant = bounds.width < 62 ? 44 : 64
            } else {
                durationLabel.text = nil
                durationLabel.isHidden = true
                mediaBadgeWidthConstraint?.constant = 28
            }
        case .livePhoto:
            mediaBadge.image = UIImage(systemName: "livephoto")
            mediaBadgeBackground.isHidden = false
            mediaBadgeBackground.backgroundColor = .clear
            durationLabel.text = nil
            durationLabel.isHidden = true
            mediaBadgeWidthConstraint?.constant = 28
        default:
            mediaBadgeBackground.isHidden = true
            durationLabel.text = nil
            durationLabel.isHidden = true
            mediaBadgeWidthConstraint?.constant = 28
        }
    }

    private func syncDotColor(for status: VaultSyncStatus) -> UIColor {
        switch status {
        case .synced:
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.56, green: 0.74, blue: 0.62, alpha: 0.62)
                    : UIColor(red: 0.32, green: 0.54, blue: 0.38, alpha: 0.50)
            }
        case .failed, .conflict:
            return UIColor.systemRed.withAlphaComponent(0.72)
        case .local, .pending:
            return UIColor.systemOrange.withAlphaComponent(0.62)
        }
    }

    private func configureSelection(isSelectionMode: Bool, isSelected: Bool) {
        isCurrentlySelected = isSelected
        selectionCircle.isHidden = !isSelectionMode
        if isSelectionMode {
            selectionCircle.backgroundColor = isSelected ? UIColor.systemBlue : UIColor.black.withAlphaComponent(0.45)
        }
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
        selectionBorder.lineWidth = isSelected ? selectionBorderWidth : 0
        updateSelectionMetrics()
    }

    private var selectionCircleSize: CGFloat {
        min(max(bounds.width * 0.22, 12), 34)
    }

    private var selectionCircleInset: CGFloat {
        min(max(bounds.width * 0.055, 3), 8)
    }

    private var selectionBorderWidth: CGFloat {
        min(max(bounds.width * 0.028, 1.5), 3)
    }

    private func updateSelectionMetrics() {
        let size = selectionCircleSize
        let inset = selectionCircleInset
        selectionCircleTopConstraint?.constant = inset
        selectionCircleLeadingConstraint?.constant = inset
        selectionCircleWidthConstraint?.constant = size
        selectionCircleHeightConstraint?.constant = size
        selectionCircle.layer.cornerRadius = size / 2
        selectionBorder.lineWidth = isCurrentlySelected ? selectionBorderWidth : 0
        if !selectionCircle.isHidden {
            selectionCircle.image = selectionImage(isSelected: isCurrentlySelected)
        }
    }

    private func selectionImage(isSelected: Bool) -> UIImage? {
        let pointSize = max(selectionCircleSize * 0.72, 9)
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        return UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle", withConfiguration: configuration)
    }

    private func iconName(for kind: VaultItemKind) -> String {
        switch kind {
        case .image: "photo"
        case .livePhoto: "livephoto"
        case .video: "video"
        case .audio: "waveform"
        case .document: "doc"
        case .archive: "archivebox"
        case .link: "link"
        case .other: "doc"
        }
    }
}

private struct MediaGridWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MediaGridItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [AnyHashable: CGRect] = [:]

    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

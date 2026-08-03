import SwiftUI
import UIKit

enum MediaGridLayout {
    static let defaultScale: CGFloat = 1
    static let minimumScale: CGFloat = 0.16
    static let maximumScale: CGFloat = 3.25
    static let baseTileMinimum: CGFloat = 108
    static let minimumTileSize: CGFloat = 24
    static let interactionMinHeight: CGFloat = 560
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
}

enum MediaGridScaleStorage {
    static let albumKey = "vault.mediaGridScale.album"
    static let audioKey = "vault.mediaGridScale.audio"
    static let documentsKey = "vault.mediaGridScale.documents"

    static let defaultStoredScale = Double(MediaGridLayout.defaultScale)
}

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
    let isSelectionMode: Bool
    let selectedItemIds: Set<String>
    let thumbnailProvider: (VaultItem) -> UIImage?
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
        collectionView.showsVerticalScrollIndicator = true
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
        collectionView.reloadData()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        var parent: AlbumZoomableMediaGrid
        weak var collectionView: UICollectionView?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var selectionPanRecognizer: UIPanGestureRecognizer?
        private var pinchStartScale: CGFloat = MediaGridLayout.defaultScale
        private var isPinching = false
        private var selectedDuringPan = Set<String>()
        private var selectedDuringLongPress = Set<String>()

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
            cell.configure(
                item: item,
                thumbnail: parent.thumbnailProvider(item),
                isSelectionMode: parent.isSelectionMode,
                isSelected: parent.selectedItemIds.contains(item.id)
            )
            return cell
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
            case .changed:
                parent.scale = MediaGridLayout.clampedScale(pinchStartScale * recognizer.scale)
                applyLayout(animated: false)
            case .ended, .cancelled, .failed:
                let snapped = MediaGridLayout.snappedScale(parent.scale, containerWidth: collectionView.bounds.width)
                UIView.animate(
                    withDuration: 0.24,
                    delay: 0,
                    usingSpringWithDamping: 0.86,
                    initialSpringVelocity: 0.2,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    self.parent.scale = snapped
                    self.applyLayout(animated: false)
                    collectionView.layoutIfNeeded()
                } completion: { _ in
                    self.isPinching = false
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

        func applyLayout(animated: Bool) {
            guard let collectionView,
                  let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
                return
            }
            let width = max(collectionView.bounds.width, MediaGridLayout.minimumTileSize)
            let tile = MediaGridLayout.tileMinimum(for: width, scale: parent.scale)
            let update = {
                layout.itemSize = CGSize(width: tile, height: tile)
                layout.invalidateLayout()
            }
            if animated {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: update)
            } else {
                update()
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
    private let mediaBadge = UIImageView()
    private let syncDot = UIView()
    private let selectionCircle = UIImageView()
    private let selectionBorder = CAShapeLayer()

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
        mediaBadge.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        mediaBadge.translatesAutoresizingMaskIntoConstraints = false

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
        contentView.addSubview(mediaBadge)
        contentView.addSubview(syncDot)
        contentView.addSubview(selectionCircle)

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

            mediaBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            mediaBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            mediaBadge.widthAnchor.constraint(equalToConstant: 28),
            mediaBadge.heightAnchor.constraint(equalToConstant: 28),

            syncDot.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            syncDot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            syncDot.widthAnchor.constraint(equalToConstant: 7),
            syncDot.heightAnchor.constraint(equalToConstant: 7),

            selectionCircle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            selectionCircle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            selectionCircle.widthAnchor.constraint(equalToConstant: 24),
            selectionCircle.heightAnchor.constraint(equalToConstant: 24)
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
        mediaBadge.layer.cornerRadius = mediaBadge.bounds.width / 2
        syncDot.layer.cornerRadius = syncDot.bounds.width / 2
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        placeholderIcon.image = nil
        placeholderLabel.text = nil
        mediaBadge.image = nil
        mediaBadge.isHidden = true
        mediaBadge.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        selectionCircle.image = nil
        selectionCircle.isHidden = true
        selectionBorder.strokeColor = UIColor.clear.cgColor
    }

    func configure(item: VaultItem, thumbnail: UIImage?, isSelectionMode: Bool, isSelected: Bool) {
        if let thumbnail {
            imageView.image = thumbnail
            imageView.isHidden = false
            placeholderIcon.isHidden = true
            placeholderLabel.isHidden = true
        } else {
            imageView.isHidden = true
            placeholderIcon.isHidden = false
            placeholderLabel.isHidden = bounds.width < 72
            placeholderIcon.image = UIImage(systemName: iconName(for: item.kind))
            placeholderLabel.text = item.kind.rawValue.uppercased()
        }

        configureGradient(for: item.kind)
        configureMediaBadge(for: item.kind)
        syncDot.backgroundColor = item.syncStatus == .synced ? UIColor.systemGreen : UIColor.systemOrange
        configureSelection(isSelectionMode: isSelectionMode, isSelected: isSelected)
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

    private func configureMediaBadge(for kind: VaultItemKind) {
        switch kind {
        case .video:
            mediaBadge.image = UIImage(systemName: "play.fill")
            mediaBadge.isHidden = false
            mediaBadge.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        case .livePhoto:
            mediaBadge.image = UIImage(systemName: "livephoto")
            mediaBadge.isHidden = false
            mediaBadge.backgroundColor = .clear
        default:
            mediaBadge.isHidden = true
            mediaBadge.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        }
    }

    private func configureSelection(isSelectionMode: Bool, isSelected: Bool) {
        selectionCircle.isHidden = !isSelectionMode
        if isSelectionMode {
            selectionCircle.backgroundColor = isSelected ? UIColor.systemBlue : UIColor.black.withAlphaComponent(0.45)
            selectionCircle.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        }
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
        selectionBorder.lineWidth = isSelected ? 3 : 0
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

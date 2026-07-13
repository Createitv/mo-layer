import SwiftUI

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

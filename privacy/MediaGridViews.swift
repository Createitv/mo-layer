import SwiftUI

enum MediaGridLayout {
    static let defaultScale: CGFloat = 1
    static let minimumScale: CGFloat = 0.72
    static let maximumScale: CGFloat = 1.6
    static let baseTileMinimum: CGFloat = 110
    static let spacing: CGFloat = 10

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func tileMinimum(for containerWidth: CGFloat, scale: CGFloat) -> CGFloat {
        let compactLimit = max(82, floor((containerWidth - spacing * 2) / 4))
        let regularLimit = max(176, floor((containerWidth - spacing * 4) / 5))
        let upperBound = containerWidth < 520 ? max(150, compactLimit * 2) : regularLimit
        return min(max(round(baseTileMinimum * clampedScale(scale)), 76), upperBound)
    }
}

struct ZoomableMediaGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    @Binding var scale: CGFloat
    let content: (Data.Element) -> Content

    @GestureState private var pinchScale: CGFloat = 1
    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width - 32

    var body: some View {
        let effectiveScale = MediaGridLayout.clampedScale(scale * pinchScale)
        let columns = [
            GridItem(
                .adaptive(minimum: MediaGridLayout.tileMinimum(for: containerWidth, scale: effectiveScale)),
                spacing: MediaGridLayout.spacing
            )
        ]

        LazyVGrid(columns: columns, spacing: MediaGridLayout.spacing) {
            ForEach(items) { item in
                content(item)
            }
        }
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
                .updating($pinchScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    scale = MediaGridLayout.clampedScale(scale * value)
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

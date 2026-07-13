import SwiftUI
import UIKit

struct VaultSelectionToolbar: View {
    let selectedCount: Int
    let isDeleting: Bool
    let canDelete: Bool
    let moveTitle: String?
    let moveSystemImage: String
    let cancelAction: () -> Void
    let moveAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: cancelAction) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text(L.format("%d selected", selectedCount))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            if let moveTitle {
                Button(action: moveAction) {
                    Label(moveTitle, systemImage: moveSystemImage)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || isDeleting)
            }

            if canDelete {
                Button(role: .destructive, action: deleteAction) {
                    Label(isDeleting ? L.string("Deleting") : L.string("Delete"), systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || isDeleting)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct VaultSelectionCheckbox: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AppTheme.primaryFill : Color.black.opacity(0.48))
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

struct SelectableVaultItemTile: View {
    let item: VaultItem
    let isSelectionMode: Bool
    let isSelected: Bool

    var body: some View {
        VaultItemTile(item: item)
            .overlay(alignment: .topLeading) {
                if isSelectionMode && item.kind.isVisualMedia {
                    VaultSelectionCheckbox(isSelected: isSelected)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                if isSelectionMode && isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.primary, lineWidth: 3)
                }
            }
    }
}

struct VaultItemPressureSelectionAction: ViewModifier {
    let item: VaultItem
    let forceAction: () -> Void
    let fallbackLongPressAction: () -> Void

    func body(content: Content) -> some View {
        if item.kind.isVisualMedia {
            content
                .background(
                    ForcePressObserver(thresholdRatio: 0.64) {
                        forceAction()
                    }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.85, maximumDistance: 18)
                        .onEnded { _ in fallbackLongPressAction() }
                )
        } else {
            content
        }
    }
}

private struct ForcePressObserver: UIViewRepresentable {
    let thresholdRatio: CGFloat
    let onForcePress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = ForcePressView()
        view.thresholdRatio = thresholdRatio
        view.onForcePress = onForcePress
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? ForcePressView else { return }
        view.thresholdRatio = thresholdRatio
        view.onForcePress = onForcePress
    }

    private final class ForcePressView: UIView {
        var thresholdRatio: CGFloat = 0.64
        var onForcePress: (() -> Void)?
        private var didTrigger = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            didTrigger = false
            evaluate(touches)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            evaluate(touches)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            didTrigger = false
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            didTrigger = false
        }

        private func evaluate(_ touches: Set<UITouch>) {
            guard !didTrigger,
                  let touch = touches.first,
                  touch.maximumPossibleForce > 0 else {
                return
            }
            let ratio = touch.force / touch.maximumPossibleForce
            guard ratio >= thresholdRatio else { return }
            didTrigger = true
            onForcePress?()
        }
    }
}

struct VaultItemLongPressAction: ViewModifier {
    let item: VaultItem
    let previewAction: () -> Void
    let detailAction: () -> Void
    var isEnabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if item.kind.usesLongPressMediaPreview {
            content
        } else {
            content.contextMenu {
                Button(action: detailAction) {
                    Label(L.string("Details"), systemImage: "info.circle")
                }
            }
        }
    }
}

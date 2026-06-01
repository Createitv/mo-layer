import SwiftUI
import UIKit

enum VaultHomeHeaderLayout {
    static let actionSize: CGFloat = 34
    static let iconFontSize: CGFloat = 17
}

struct VaultHomeHeader: View {
    @Binding var selectedCategory: VaultCategory
    let isInnerVaultActive: Bool
    let profileAction: () -> Void
    let importAction: () -> Void
    let toggleInnerVaultAction: () -> Void
    @State private var hiddenTapCount = 0
    @State private var hiddenTapResetTask: Task<Void, Never>?
    #if os(iOS)
    @State private var hiddenEntryFeedback = UINotificationFeedbackGenerator()
    #endif

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            categoryMenu

            // 暗格入口：连续点击标题和右侧按钮之间的空白区域三次。
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleHiddenAreaTap)
                .accessibilityHidden(true)

            headerIconButton(systemName: "person.crop.circle", accessibilityLabel: L.string("Profile"), action: profileAction)

            headerIconButton(systemName: "tray.and.arrow.down", accessibilityLabel: L.string("Import"), action: importAction)
        }
        .frame(minHeight: 44)
        .onDisappear {
            hiddenTapResetTask?.cancel()
        }
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(VaultCategory.homeModes) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(category.title, systemImage: category.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedCategory.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.string("Switch Category"))
    }

    private func headerIconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: VaultHomeHeaderLayout.iconFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: VaultHomeHeaderLayout.actionSize, height: VaultHomeHeaderLayout.actionSize)
                .background(AppTheme.primary.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func handleHiddenAreaTap() {
        hiddenTapResetTask?.cancel()
        hiddenTapCount += 1

        guard hiddenTapCount >= 3 else {
            #if os(iOS)
            hiddenEntryFeedback.prepare()
            #endif
            hiddenTapResetTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                hiddenTapCount = 0
            }
            return
        }

        hiddenTapCount = 0
        #if os(iOS)
        hiddenEntryFeedback.notificationOccurred(.success)
        #endif
        toggleInnerVaultAction()
    }
}

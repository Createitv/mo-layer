import SwiftUI
import UIKit

enum VaultHomeHeaderLayout {
    static let actionSize: CGFloat = 34
    static let iconFontSize: CGFloat = 17
}

enum VaultFolderContextStyle: Equatable {
    case regular
    case moLayer

    init(isInnerVaultActive: Bool) {
        self = isInnerVaultActive ? .moLayer : .regular
    }

    var trailingActions: [MainShellAction] {
        switch self {
        case .regular:
            return [.profile, .import]
        case .moLayer:
            return [.import]
        }
    }

    var showsProfileAction: Bool {
        trailingActions.contains(.profile)
    }

    var profileSystemImage: String {
        switch self {
        case .regular: "person.crop.circle"
        case .moLayer: "person.crop.circle.badge.checkmark"
        }
    }

    var importSystemImage: String {
        switch self {
        case .regular: "tray.and.arrow.down"
        case .moLayer: "square.stack.3d.down.right.fill"
        }
    }

    var actionForeground: Color {
        switch self {
        case .regular: AppTheme.primary
        case .moLayer: AppTheme.warning
        }
    }

    var actionBackground: Color {
        switch self {
        case .regular: AppTheme.primary.opacity(0.08)
        case .moLayer: AppTheme.warning.opacity(0.14)
        }
    }
}

struct VaultHomeHeader: View {
    @Binding var selectedCategory: VaultCategory
    let isInnerVaultActive: Bool
    let profileAction: () -> Void
    let importAction: () -> Void
    let toggleInnerVaultAction: () -> Void
    var onTouchZoneFrameChange: (CGRect) -> Void = { _ in }
    @State private var hiddenTapCount = 0
    @State private var hiddenTapResetTask: Task<Void, Never>?
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var hiddenEntryFeedback = UINotificationFeedbackGenerator()
    #endif

    var body: some View {
        let contextStyle = VaultFolderContextStyle(isInnerVaultActive: isInnerVaultActive)

        HStack(alignment: .center, spacing: 12) {
            categoryMenu
                .layoutPriority(1)

            // 暗格入口：连续点击标题和右侧按钮之间的空白区域三次。
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: VaultHomeHeaderTouchZoneFramePreferenceKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                )
                .onTapGesture(perform: handleHiddenAreaTap)
                .accessibilityHidden(true)
                .layoutPriority(0)

            if contextStyle.showsProfileAction {
                headerIconButton(
                    systemName: contextStyle.profileSystemImage,
                    accessibilityLabel: L.string("Profile"),
                    contextStyle: contextStyle,
                    action: profileAction
                )
            }

            headerIconButton(
                systemName: contextStyle.importSystemImage,
                accessibilityLabel: L.string("Import"),
                contextStyle: contextStyle,
                action: importAction
            )
        }
        .frame(height: 44)
        .animation(.smooth(duration: 0.18), value: contextStyle)
        .onDisappear {
            hiddenTapResetTask?.cancel()
        }
        .onPreferenceChange(VaultHomeHeaderTouchZoneFramePreferenceKey.self) { frame in
            guard frame != .zero else { return }
            onTouchZoneFrameChange(frame)
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
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.string("Switch Category"))
    }

    private func headerIconButton(
        systemName: String,
        accessibilityLabel: String,
        contextStyle: VaultFolderContextStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: VaultHomeHeaderLayout.iconFontSize, weight: .semibold))
                .foregroundStyle(contextStyle.actionForeground)
                .frame(width: VaultHomeHeaderLayout.actionSize, height: VaultHomeHeaderLayout.actionSize)
                .background(contextStyle.actionBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func handleHiddenAreaTap() {
        hiddenTapResetTask?.cancel()
        hiddenTapCount += 1

        guard hiddenTapCount >= 3 else {
            #if os(iOS) && !targetEnvironment(macCatalyst)
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
        #if os(iOS) && !targetEnvironment(macCatalyst)
        hiddenEntryFeedback.notificationOccurred(.success)
        #endif
        toggleInnerVaultAction()
    }
}

private struct VaultHomeHeaderTouchZoneFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

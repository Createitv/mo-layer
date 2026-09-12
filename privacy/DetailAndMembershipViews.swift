import RevenueCat
import SwiftData
import SwiftUI

struct VaultItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    @Query(sort: \VaultFolder.sortOrder) private var folders: [VaultFolder]
    let item: VaultItem
    @State private var sharePayload: SharePayload?
    @State private var previewItem: VaultItem?
    @State private var isPreparingShare = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vaultStore.metadata(for: item)?.originalName ?? L.string("Private Item"))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(detailLine)
                            .foregroundStyle(AppTheme.secondaryText)
                        HStack {
                            StatusPill(title: L.string("Encrypted Storage"), systemImage: "lock.doc", tint: AppTheme.success)
                            StatusPill(title: item.syncStatus.title, systemImage: "icloud", tint: item.syncStatus == .failed ? AppTheme.warning : AppTheme.primary)
                            StatusPill(title: item.assetState.title, systemImage: item.assetState.systemImage, tint: item.assetState == .failed ? AppTheme.warning : AppTheme.primary)
                        }
                        if item.syncStatus == .failed {
                            Text(item.lastSyncError ?? sync.lastSyncError ?? L.string("Unable to upload this item to iCloud."))
                                .font(.caption)
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if item.assetState == .failed, let lastDownloadError = item.lastDownloadError {
                            Text(lastDownloadError)
                                .font(.caption)
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let image = vaultStore.thumbnail(for: item) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
                } else {
                    Image(systemName: placeholderDescriptor.icon)
                        .font(.system(size: 72))
                        .foregroundStyle(placeholderDescriptor.tint)
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .background(placeholderDescriptor.tint.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if item.kind.isDocumentPreview {
                    Button {
                        previewItem = item
                    } label: {
                        Label(L.string("Preview"), systemImage: placeholderDescriptor.icon)
                    }
                    .buttonStyle(AppButtonStyle())
                }

                if item.kind == .link, let urlString = vaultStore.metadata(for: item)?.remoteURL, let url = URL(string: urlString) {
                    Button {
                        sharePayload = SharePayload(items: [url])
                    } label: {
                        Label(L.string("Share to Other Apps"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(AppButtonStyle())
                } else {
                    Button {
                        Task { await prepareShare() }
                    } label: {
                        Label(isPreparingShare ? L.string("Preparing") : L.string("Share to Other Apps"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(AppButtonStyle())
                    .disabled(isPreparingShare)
                }

                if subscription.canImportAndSync {
                    Picker(L.string("Move to Album"), selection: Binding(
                        get: { item.folderId ?? "" },
                        set: { newValue in
                            Task {
                                let folder = folders.first { $0.id == newValue }
                                await vaultStore.move(item, to: folder, context: modelContext, sync: sync)
                            }
                        }
                    )) {
                        Text(L.string("No Album")).tag("")
                        ForEach(folders.filter { $0.deletedAt == nil && $0.id != VaultStore.innerVaultFolderId }) { folder in
                            Text(vaultStore.folderName(folder)).tag(folder.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
                }

                if subscription.canImportAndSync {
                    Button(role: .destructive) {
                        Task {
                            await vaultStore.deleteImmediately(item, context: modelContext, sync: sync)
                            dismiss()
                        }
                    } label: {
                        Label(L.string("Delete"), systemImage: "trash")
                    }
                    .buttonStyle(AppButtonStyle(role: .destructive))
                }
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle(L.string("Private Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await vaultStore.toggleFavorite(item, context: modelContext, sync: sync)
                        }
                    } label: {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel(item.isFavorite ? L.string("Unfavorite") : L.string("Favorite"))

                    Menu {
                        Button {
                            Task { await prepareShare() }
                        } label: {
                            Label(L.string("Export"), systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .fullScreenCover(item: $previewItem) { item in
                DocumentDetailPreviewView(
                    item: item,
                    isInnerVaultActive: item.folderId == VaultStore.innerVaultFolderId
                )
            }
        }
    }

    @MainActor
    private func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        if item.kind == .link, let urlString = vaultStore.metadata(for: item)?.remoteURL, let url = URL(string: urlString) {
            sharePayload = SharePayload(items: [url])
            return
        }
        guard let url = try? await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync) else { return }
        sharePayload = SharePayload(items: [url])
    }

    private var detailLine: String {
        "\(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)) · \(item.syncStatus.title)"
    }

    private var placeholderDescriptor: VaultFileDisplayDescriptor {
        VaultFileDisplayDescriptor(metadata: vaultStore.metadata(for: item), kind: item.kind)
    }
}

enum MembershipPresentationContext {
    case navigation
    case modal

    var showsDismissControl: Bool {
        self == .modal
    }
}

struct MembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscription: SubscriptionManager
    var isRequiredBeforeUse = false
    let presentationContext: MembershipPresentationContext
    #if DEBUG
    @State private var previewsPaywall = ProcessInfo.processInfo.arguments.contains("-review-membership-capture")
    #endif

    private var showsActiveMembership: Bool {
        #if DEBUG
        subscription.isPro && !previewsPaywall
        #else
        subscription.isPro
        #endif
    }

    @State private var selectedProductID = SubscriptionManager.yearly
    @State private var isRestoringPurchases = false
    @State private var isRedeemingOfferCode = false
    @State private var showOfferCodeInstructions = false

    init(
        isRequiredBeforeUse: Bool = false,
        presentationContext: MembershipPresentationContext = .navigation
    ) {
        self.isRequiredBeforeUse = isRequiredBeforeUse
        self.presentationContext = presentationContext
    }

    @Query private var vaultItems: [VaultItem]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showsActiveMembership {
                        activeMembershipCard
                    } else {
                        membershipHero
                        Text(L.string("No app storage limit. Backups use your own iCloud storage."))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L.string("Choose your Pro plan"))
                                .font(.title3.bold())
                            ForEach(displayPackages, id: \.storeProduct.productIdentifier) { package in
                                membershipPlan(package)
                            }
                            if subscription.loadState == .loading {
                                ProgressView(L.string("Loading subscription plans..."))
                            }
                            if case .failed(let message) = subscription.loadState {
                                Text(message).font(.callout).foregroundStyle(AppTheme.warning)
                                Button(L.string("Retry")) { Task { await subscription.load() } }
                            } else if subscription.loadState == .loaded && displayPackages.isEmpty {
                                Text(L.string("Membership plans are currently unavailable. You can keep using your free storage."))
                                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }

                    if let feedback = subscription.restoreFeedback {
                        RestorePurchaseFeedbackView(feedback: feedback)
                    } else if let statusMessage {
                        Text(statusMessage).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    VStack(spacing: 16) {
                        HStack(spacing: 24) {
                            Button(L.string("Restore Purchases")) { restorePurchases() }
                                .accessibilityIdentifier("membership.restoreAfterReinstall")
                            Button(L.string("Redeem Code")) { redeemOfferCode() }
                        }
                        .disabled(isRestoringPurchases || isRedeemingOfferCode || subscription.isPurchasing)
                        HStack(spacing: 24) {
                            Link(L.string("Privacy Policy"), destination: SubscriptionManager.privacyPolicyURL)
                            Link(L.string("Terms of Use"), destination: SubscriptionManager.termsOfUseURL)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                if !showsActiveMembership {
                    VStack(spacing: 10) {
                        Button {
                            #if DEBUG
                            guard !previewsPaywall else { return }
                            #endif
                            guard let selectedPackage else { return }
                            Task { await subscription.purchase(selectedPackage) }
                        } label: {
                            HStack {
                                if subscription.isPurchasing { ProgressView().tint(.white) }
                                Text(selectedPackage.map(actionTitle) ?? L.string("Open Pro"))
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white)
                            .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedPackage == nil || subscription.isPurchasing || subscription.loadState == .loading)
                        .opacity(selectedPackage == nil ? 0.5 : 1)
                        .accessibilityIdentifier("membership.purchase")
                        if let selectedPackage {
                            Text(purchaseDisclosure(for: selectedPackage))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(L.string("Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                if showsActiveMembership {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Preview Paywall", systemImage: "eye") { previewsPaywall = true }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("membership.previewPaywall")
                    }
                }
                #endif
                if presentationContext.showsDismissControl {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.string("Close")) { dismiss() }
                            .accessibilityIdentifier("membership.close")
                    }
                }
            }
            .alert(L.string("Redeem Code"), isPresented: $showOfferCodeInstructions) {
                Button(L.string("OK"), role: .cancel) {}
            } message: {
                Text(L.string("Open the App Store, select your account, choose Redeem Gift Card or Code, then return to Mo Layer and tap Restore Purchases."))
            }
            .task {
                await subscription.load()
                selectDefaultPackageIfNeeded()
            }
            .onChange(of: subscription.packages.map(\.storeProduct.productIdentifier)) { _, _ in
                selectDefaultPackageIfNeeded()
            }
        }
    }

    private var storageCard: some View {
        let used = VaultStoragePolicy.usedBytes(in: vaultItems)
        let progress = min(Double(used) / Double(VaultStoragePolicy.freeByteLimit), 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L.string("Your library"), systemImage: "externaldrive")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(showsActiveMembership ? L.string("Pro Active") : L.string("Free · 5 GB"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                if !showsActiveMembership {
                    Text("/ 5 GB").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
            }
            if !showsActiveMembership {
                ProgressView(value: progress).tint(progress >= 1 ? AppTheme.warning : AppTheme.primary)
            }
            Text(L.string("Counts files in every folder, including cloud-only files. No file count limit."))
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(20)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var activeMembershipCard: some View {
        let summary = subscription.membershipStatusSummary
        let used = VaultStoragePolicy.usedBytes(in: vaultItems)
        return VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(summary.planTitle)
                    .font(.title2.bold())
                Spacer(minLength: 8)
                Label(summary.stateTitle, systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.primary)

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "infinity")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityHidden(true)
                Text(L.string("Unlimited vault storage"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if !summary.expirationText.isEmpty {
                    Text(summary.expirationText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Divider()
            HStack {
                Text(L.string("Your library"))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            Text(L.string("No app storage limit. Backups use your own iCloud storage."))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("membership.activeCard")
    }

    private func membershipPlan(_ package: Package) -> some View {
        let selected = selectedProductID == package.storeProduct.productIdentifier
        return Button {
            selectedProductID = package.storeProduct.productIdentifier
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected ? AppTheme.primary : AppTheme.secondaryText)
                VStack(alignment: .leading, spacing: 5) {
                    Text(localizedName(for: package)).font(.headline)
                    if let badge = badgeTitle(for: package) {
                        Text(badge).font(.caption.weight(.medium)).foregroundStyle(AppTheme.primary)
                    }
                }
                Spacer(minLength: 8)
                Text(package.localizedPriceString).font(.title3.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(AppTheme.ink)
            .padding(18)
            .background(selected ? AppTheme.primary.opacity(0.07) : AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? AppTheme.primary : AppTheme.line, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func purchaseDisclosure(for package: Package) -> String {
        if package.storeProduct.productIdentifier == SubscriptionManager.lifetime {
            return L.format("%@ once. No subscription renewal.", package.localizedPriceString)
        }
        let price = package.localizedPriceString
        let period = package.storeProduct.productIdentifier == SubscriptionManager.yearly ? L.string("year") : L.string("month")
        if subscription.offersThreeDayTrial(package) {
            return L.format("3 days free, then %@ / %@. Renews automatically unless canceled in Apple subscription settings.", price, period)
        }
        return L.format("%@ / %@. Renews automatically unless canceled in Apple subscription settings. Trial eligibility is confirmed by Apple.", price, period)
    }

    private func restorePurchases() {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        Task { @MainActor in
            await subscription.restorePurchases()
            isRestoringPurchases = false
        }
    }

    private func redeemOfferCode() {
        guard !isRedeemingOfferCode else { return }
        guard OfferCodePresentationPolicy.action(for: PlatformCapabilities.routes.offerCode) == .openSystemSheet else {
            showOfferCodeInstructions = true
            return
        }
        isRedeemingOfferCode = true
        Task { @MainActor in
            await subscription.redeemOfferCode()
            isRedeemingOfferCode = false
        }
    }

    private var displayPackages: [Package] {
        subscription.packages.sorted {
            SubscriptionManager.displayOrder(forStoreProductID: $0.storeProduct.productIdentifier) <
            SubscriptionManager.displayOrder(forStoreProductID: $1.storeProduct.productIdentifier)
        }
    }

    private var selectedPackage: Package? {
        subscription.packages.first { $0.storeProduct.productIdentifier == selectedProductID } ?? displayPackages.last
    }

    private var statusMessage: String? {
        if subscription.isPro {
            return nil
        }
        if case .failed = subscription.loadState {
            return nil
        }
        return subscription.statusText
    }

    private var membershipHero: some View {
        Label(L.string("Unlimited vault storage"), systemImage: "infinity")
            .font(.title2.bold())
            .foregroundStyle(AppTheme.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func selectDefaultPackageIfNeeded() {
        let productIDs = displayPackages.map(\.storeProduct.productIdentifier)
        guard !productIDs.contains(selectedProductID) else { return }
        if productIDs.contains(SubscriptionManager.yearly) {
            selectedProductID = SubscriptionManager.yearly
        } else if let fallback = productIDs.last {
            selectedProductID = fallback
        }
    }

    private func localizedName(for package: Package) -> String {
        let product = package.storeProduct
        switch product.productIdentifier {
        case SubscriptionManager.monthly:
            return L.string("Monthly Pro")
        case SubscriptionManager.yearly:
            return L.string("Yearly Pro")
        case SubscriptionManager.lifetime:
            return L.string("Lifetime Pro")
        default:
            if shouldUseStoreKitText(product.localizedTitle) {
                return product.localizedTitle
            }
            return product.localizedTitle
        }
    }

    private func localizedName(forProductID productID: String) -> String {
        switch productID {
        case SubscriptionManager.monthly:
            return L.string("Monthly Pro")
        case SubscriptionManager.yearly:
            return L.string("Yearly Pro")
        case SubscriptionManager.lifetime:
            return L.string("Lifetime Pro")
        default:
            return productID
        }
    }

    private func actionTitle(for package: Package) -> String {
        if subscription.offersThreeDayTrial(package) { return L.string("Start 3-Day Trial") }
        return package.storeProduct.productIdentifier == SubscriptionManager.lifetime
            ? L.string("Unlock Lifetime") : L.string("Open Pro")
    }

    private func badgeTitle(for package: Package) -> String? {
        if subscription.offersThreeDayTrial(package) { return L.string("3-day trial") }
        return package.storeProduct.productIdentifier == SubscriptionManager.yearly ? L.string("Better value") : nil
    }

    private func shouldUseStoreKitText(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if AppLanguage.current == .simplifiedChinese || AppLanguage.current == .traditionalChinese {
            return true
        }
        return !text.containsChineseMembershipText
    }
}

private struct RestorePurchaseFeedbackView: View {
    let feedback: RestorePurchaseFeedback

    var body: some View {
        Label(feedback.message, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tint: Color {
        switch feedback.kind {
        case .success:
            AppTheme.success
        case .warning:
            AppTheme.warning
        }
    }

    private var systemImage: String {
        switch feedback.kind {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        }
    }
}

private extension String {
    var containsChineseMembershipText: Bool {
        [
            "会员",
            "月度",
            "年度",
            "终身",
            "私密",
            "保险箱",
            "购买",
            "免费版",
            "解锁",
            "恢复购买"
        ].contains { contains($0) }
    }
}

private struct ProPaywallLayout {
    let width: CGFloat

    private var contentWidth: CGFloat {
        max(width - screenPadding * 2, 1)
    }

    var isCompact: Bool {
        width < 390
    }

    var screenPadding: CGFloat {
        width < 390 ? 14 : 16
    }

    var sectionSpacing: CGFloat {
        width < 390 ? 13 : 16
    }

    var planSpacing: CGFloat {
        width < 390 ? 8 : 10
    }

    var heroImageHeight: CGFloat {
        min(max(width * 0.46, 168), 226)
    }

    var heroTitleSize: CGFloat {
        min(max(width * 0.076, 27), 34)
    }

    var heroSubtitleSize: CGFloat {
        width < 390 ? 14 : 15
    }

    var accessLabelSize: CGFloat {
        width < 390 ? 12 : 13
    }

    var accessTitleSize: CGFloat {
        width < 390 ? 16 : 18
    }

    var accessIconSize: CGFloat {
        width < 390 ? 32 : 36
    }

    var planTitleSize: CGFloat {
        width < 390 ? 15 : 17
    }

    var planPriceSize: CGFloat {
        width < 390 ? 25 : 30
    }

    var planBadgeSize: CGFloat {
        width < 390 ? 11 : 12
    }

    var planCardHeight: CGFloat {
        let availableCardWidth = (contentWidth - planSpacing * 2) / 3
        return max(142, min(availableCardWidth * 1.44, 170))
    }

    var planHorizontalPadding: CGFloat {
        width < 390 ? 7 : 10
    }
}

private struct ProAccessComparisonCard: View {
    let isPro: Bool
    let layout: ProPaywallLayout

    var body: some View {
        HStack(spacing: 0) {
            ProAccessColumn(
                label: L.string("Free state"),
                title: L.string("View encrypted files"),
                systemImage: "eye.fill",
                trailingSystemImage: "checkmark.circle.fill",
                tint: AppTheme.primary,
                layout: layout
            )

            Rectangle()
                .fill(AppTheme.line)
                .frame(width: 1, height: layout.isCompact ? 64 : 72)
                .padding(.horizontal, layout.isCompact ? 8 : 12)

            ProAccessColumn(
                label: L.string("Open Pro"),
                title: L.string("Keep adding encrypted files"),
                systemImage: "plus.circle.fill",
                trailingSystemImage: isPro ? "checkmark.circle.fill" : "lock.fill",
                tint: AppTheme.warning,
                layout: layout
            )
        }
        .padding(layout.isCompact ? 13 : 16)
        .background(
            LinearGradient(
                colors: [AppTheme.card.opacity(0.88), AppTheme.card.opacity(0.64)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.line.opacity(0.75)))
    }
}

private struct MembershipStatusCard: View {
    let summary: MembershipStatusSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(L.string("Current Membership"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        StatusPill(title: summary.stateTitle, systemImage: statusPillImage, tint: tint)
                    }
                    Text(summary.planTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if !summary.expirationText.isEmpty {
                        Text(summary.expirationText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer(minLength: 0)
            }

            Text(summary.detailText)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppTheme.card.opacity(0.92), tint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(0.28)))
    }

    private var tint: Color {
        switch summary.accessLevel {
        case .activePro:
            AppTheme.success
        case .expiredReadOnly:
            AppTheme.warning
        case .lockedUntilPro:
            AppTheme.primary
        }
    }

    private var systemImage: String {
        switch summary.accessLevel {
        case .activePro:
            "checkmark.seal.fill"
        case .expiredReadOnly:
            "eye.fill"
        case .lockedUntilPro:
            "person.crop.circle.badge.questionmark"
        }
    }

    private var statusPillImage: String {
        switch summary.accessLevel {
        case .activePro:
            "checkmark.circle.fill"
        case .expiredReadOnly:
            "clock.arrow.circlepath"
        case .lockedUntilPro:
            "circle"
        }
    }
}

private struct ProAccessColumn: View {
    let label: String
    let title: String
    let systemImage: String
    let trailingSystemImage: String
    let tint: Color
    let layout: ProPaywallLayout

    var body: some View {
        VStack(spacing: 11) {
            Text(label)
                .font(.system(size: layout.accessLabelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: layout.isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: layout.accessIconSize, height: layout.accessIconSize)
                    .background(tint.opacity(0.16))
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: layout.accessTitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Image(systemName: trailingSystemImage)
                    .font(.system(size: layout.isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: layout.isCompact ? 16 : 18)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProPlanOptionCard: View {
    let title: String
    let price: String
    let productID: String
    let badge: String?
    let layout: ProPaywallLayout
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: layout.isCompact ? 11 : 13) {
                VStack(spacing: layout.isCompact ? 6 : 7) {
                    Text(title)
                        .font(.system(size: layout.planTitleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)

                    Text(price)
                        .font(.system(size: layout.planPriceSize, weight: .bold, design: .rounded))
                        .foregroundStyle(isLifetime ? AppTheme.warning : AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.52)
                }

                if !isLifetime {
                    Text(badge ?? subtitle)
                        .font(.system(size: layout.planBadgeSize, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                        .padding(.horizontal, layout.isCompact ? 7 : 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: layout.isCompact ? 25 : 28, weight: .bold))
                    .foregroundStyle(isSelected ? selectionTint : AppTheme.secondaryText.opacity(0.55))
            }
            .frame(maxWidth: .infinity, minHeight: layout.planCardHeight)
            .padding(.horizontal, layout.planHorizontalPadding)
            .padding(.vertical, layout.isCompact ? 13 : 15)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? selectionTint.opacity(0.82) : AppTheme.line, lineWidth: isSelected ? 1.8 : 1)
            )
            .shadow(color: isSelected ? selectionTint.opacity(0.34) : .clear, radius: 16, x: 0, y: 8)
            .overlay(alignment: .topTrailing) {
                if isLifetime {
                    Text(L.string("Recommended"))
                        .font(.system(size: layout.isCompact ? 10 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.09, green: 0.07, blue: 0.02))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, layout.isCompact ? 8 : 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.warning)
                        .clipShape(Capsule())
                        .offset(x: layout.isCompact ? 5 : 8, y: -13)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var isLifetime: Bool {
        productID == SubscriptionManager.lifetime
    }

    private var selectionTint: Color {
        isLifetime ? AppTheme.warning : AppTheme.primary
    }

    private var subtitle: String {
        if isLifetime {
            return L.string("Pay once")
        }
        return L.string("3-day trial")
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: isSelected
            ? [AppTheme.primary.opacity(0.18), AppTheme.card.opacity(0.95)]
            : [AppTheme.card.opacity(0.94), AppTheme.card.opacity(0.86)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ProPlanPlaceholderCard: View {
    let title: String
    let badge: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.icloud")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.warning)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.warning.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(L.string("Plan is not available right now"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .background(AppTheme.card.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.warning.opacity(0.28)))
    }
}

private struct LifetimePlanCard: View {
    let title: String
    let description: String
    let price: String
    let purchaseAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.warning)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.warning.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        StatusPill(title: L.string("Best choice"), systemImage: "checkmark.seal.fill", tint: AppTheme.warning)
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(price)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text(L.string("one-time"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
            }

            Button(action: purchaseAction) {
                Label(L.string("Unlock Lifetime"), systemImage: "lock.open.fill")
            }
            .buttonStyle(AppButtonStyle())

            Text(L.string("No monthly renewal. No yearly renewal. Keep Pro access after purchase."))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.warning.opacity(0.45), lineWidth: 1.5))
    }
}

private struct SubscriptionPlanRow: View {
    let title: String
    let description: String
    let price: String
    let badge: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.primarySoft)
                            .clipShape(Capsule())
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(L.string("after trial"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Button(actionTitle, action: action)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
    }
}

private struct MarketingMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.background.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line.opacity(0.55)))
    }
}

struct FeatureLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundStyle(AppTheme.ink)
            .font(.subheadline)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

extension VaultSyncStatus {
    var title: String {
        switch self {
        case .local: L.string("Local")
        case .pending: L.string("Pending")
        case .synced: L.string("Synced")
        case .failed: L.string("Failed")
        case .conflict: L.string("Conflict")
        }
    }
}

extension VaultAssetState {
    var title: String {
        switch self {
        case .local: L.string("Available on Device")
        case .cloudOnly: L.string("Cloud Only")
        case .downloading: L.string("Downloading")
        case .failed: L.string("Download Failed")
        }
    }

    var systemImage: String {
        switch self {
        case .local: "externaldrive.fill"
        case .cloudOnly: "icloud"
        case .downloading: "icloud.and.arrow.down"
        case .failed: "exclamationmark.icloud"
        }
    }
}

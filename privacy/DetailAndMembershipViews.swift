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
                    Image(systemName: item.kind == .video ? "video.fill" : "doc.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .background(AppTheme.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                ToolbarItem(placement: .topBarTrailing) {
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
}

struct MembershipView: View {
    @EnvironmentObject private var subscription: SubscriptionManager
    var isRequiredBeforeUse = false

    init(isRequiredBeforeUse: Bool = false) {
        self.isRequiredBeforeUse = isRequiredBeforeUse
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    membershipHero

                    if subscription.loadState == .loading {
                        ProgressView(L.string("Loading subscription plans..."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }

                    if case .failed(let message) = subscription.loadState {
                        AppCard {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(AppTheme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let lifetimePackage {
                        LifetimePlanCard(
                            title: localizedName(for: lifetimePackage),
                            description: localizedDescription(for: lifetimePackage),
                            price: lifetimePackage.localizedPriceString,
                            purchaseAction: { Task { await subscription.purchase(lifetimePackage) } }
                        )
                    }

                    VStack(spacing: 10) {
                        ForEach(secondaryPackages, id: \.storeProduct.productIdentifier) { package in
                            SubscriptionPlanRow(
                                title: localizedName(for: package),
                                description: localizedDescription(for: package),
                                price: package.localizedPriceString,
                                badge: package.storeProduct.productIdentifier == SubscriptionManager.yearly ? L.string("Better value") : L.string("Flexible"),
                                actionTitle: actionTitle(for: package),
                                action: { Task { await subscription.purchase(package) } }
                            )
                        }
                    }

                    ForEach(subscription.missingProductIDs, id: \.self) { productID in
                        AppCard {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.icloud")
                                    .foregroundStyle(AppTheme.warning)
                                    .frame(width: 32, height: 32)
                                    .background(AppTheme.warning.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(localizedName(forProductID: productID))
                                        .font(.headline)
                                    Text(L.string("Not returned by RevenueCat. Check the current offering and App Store Connect availability for this plan."))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                            }
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L.string("Everything Pro protects"))
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            VStack(alignment: .leading, spacing: 8) {
                                FeatureLine(L.string("Save unlimited photos, videos, audio, and files"))
                                FeatureLine(L.string("Always-on encrypted iCloud sync"))
                                FeatureLine(L.string("Disguised entry and decoy passcode space"))
                                FeatureLine(L.string("Quick recording, Live Photos, and private previews"))
                                FeatureLine(L.string("Intrusion records and advanced recovery"))
                            }
                        }
                    }

                    Button {
                        Task { await subscription.restorePurchases() }
                    } label: {
                        Label(L.string("Restore Purchases"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(L.string("Pro"))
            .task {
                await subscription.load()
            }
        }
    }

    private var lifetimePackage: Package? {
        subscription.packages.first { $0.storeProduct.productIdentifier == SubscriptionManager.lifetime }
    }

    private var secondaryPackages: [Package] {
        subscription.packages.filter { $0.storeProduct.productIdentifier != SubscriptionManager.lifetime }
    }

    private var membershipHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StatusPill(title: L.string("Recommended"), systemImage: "sparkles", tint: AppTheme.warning)
                Spacer()
                StatusPill(title: L.string("3-day trial"), systemImage: "clock", tint: AppTheme.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L.string("Own your private vault for life"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.string("Choose Lifetime Pro once and keep the full private vault experience without another subscription renewal."))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                MarketingMetric(value: L.string("One-time"), label: L.string("payment"))
                MarketingMetric(value: L.string("Private"), label: L.string("by design"))
                MarketingMetric(value: L.string("iCloud"), label: L.string("encrypted sync"))
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [AppTheme.primary.opacity(0.13), AppTheme.warning.opacity(0.12), AppTheme.card],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.primary.opacity(0.18)))
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

    private func localizedDescription(for package: Package) -> String {
        let product = package.storeProduct
        switch product.productIdentifier {
        case SubscriptionManager.monthly:
            return L.string("Try Pro for 3 days, then continue monthly. Cancel anytime in Apple ID settings.")
        case SubscriptionManager.yearly:
            return L.string("Try Pro for 3 days, then keep a lower yearly price for long-term protection.")
        case SubscriptionManager.lifetime:
            return L.string("Pay once to unlock current Pro vault features permanently for this Apple ID.")
        default:
            if shouldUseStoreKitText(product.localizedDescription) {
                return product.localizedDescription
            }
            return product.localizedDescription
        }
    }

    private func actionTitle(for package: Package) -> String {
        switch package.storeProduct.productIdentifier {
        case SubscriptionManager.monthly, SubscriptionManager.yearly:
            return L.string("Start 3-Day Trial")
        case SubscriptionManager.lifetime:
            return L.string("Unlock Lifetime")
        default:
            return package.localizedPriceString
        }
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

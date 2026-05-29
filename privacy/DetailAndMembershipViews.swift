import RevenueCat
import SwiftData
import SwiftUI

struct VaultItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
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
                            StatusPill(title: item.assetState.title, systemImage: item.assetState.systemImage, tint: item.assetState == .failed ? AppTheme.warning : AppTheme.primary)
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
                    ForEach(folders.filter { $0.deletedAt == nil }) { folder in
                        Text(vaultStore.folderName(folder)).tag(folder.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))

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
                VStack(spacing: 16) {
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

                    ForEach(subscription.packages, id: \.storeProduct.productIdentifier) { package in
                        AppCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(localizedName(for: package))
                                        .font(.headline)
                                    Text(localizedDescription(for: package))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Button(actionTitle(for: package)) {
                                    Task { await subscription.purchase(package) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.primary)
                            }
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
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureLine(L.string("Save unlimited photos, videos, and files"))
                            FeatureLine(L.string("Batch import and advanced organization"))
                            FeatureLine(L.string("Disguised entry and decoy passcode space"))
                            FeatureLine(L.string("Intrusion records and advanced recovery"))
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

    private func localizedName(for package: Package) -> String {
        let product = package.storeProduct
        if shouldUseStoreKitText(product.localizedTitle) {
            return product.localizedTitle
        }
        switch product.productIdentifier {
        case SubscriptionManager.monthly:
            return L.string("Monthly Pro")
        case SubscriptionManager.yearly:
            return L.string("Yearly Pro")
        case SubscriptionManager.lifetime:
            return L.string("Lifetime Pro")
        default:
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
        if shouldUseStoreKitText(product.localizedDescription) {
            return product.localizedDescription
        }
        switch product.productIdentifier {
        case SubscriptionManager.monthly:
            return L.string("Monthly access to Pro vault features.")
        case SubscriptionManager.yearly:
            return L.string("Best value yearly access to Pro vault features.")
        case SubscriptionManager.lifetime:
            return L.string("One-time unlock for current Pro vault features.")
        default:
            return product.localizedDescription
        }
    }

    private func actionTitle(for package: Package) -> String {
        switch package.storeProduct.productIdentifier {
        case SubscriptionManager.monthly, SubscriptionManager.yearly:
            return L.string("Start 7-Day Trial")
        case SubscriptionManager.lifetime:
            return package.localizedPriceString
        default:
            return package.localizedPriceString
        }
    }

    private func shouldUseStoreKitText(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if AppLanguage.current == .simplifiedChinese {
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

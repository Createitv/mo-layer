import QuickLook
import StoreKit
import SwiftData
import SwiftUI

struct VaultItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    @Query(sort: \VaultFolder.sortOrder) private var folders: [VaultFolder]
    let item: VaultItem
    @State private var previewURL: URL?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vaultStore.metadata(for: item)?.originalName ?? L.string("Private Item"))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text("\(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)) · \(item.syncStatus.title)")
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
                        openURL(url)
                    } label: {
                        Label("Open Link", systemImage: "safari")
                    }
                    .buttonStyle(AppButtonStyle())
                } else {
                    Button {
                        Task {
                            previewURL = try? await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
                        }
                    } label: {
                        Label(item.assetState == .cloudOnly ? L.string("Download and Preview") : L.string("Temporary Decrypted Preview"), systemImage: "eye")
                    }
                    .buttonStyle(AppButtonStyle())
                }

                Button {
                    Task {
                        shareURL = try? await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
                    }
                } label: {
                    Label("Export with System Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())

                Picker("Move to Album", selection: Binding(
                    get: { item.folderId ?? "" },
                    set: { newValue in
                        Task {
                            let folder = folders.first { $0.id == newValue }
                            await vaultStore.move(item, to: folder, context: modelContext, sync: sync)
                        }
                    }
                )) {
                    Text("No Album").tag("")
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
                        await vaultStore.moveToTrash(item, context: modelContext, sync: sync)
                        dismiss()
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .buttonStyle(AppButtonStyle(role: .destructive))
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle("Private Item")
            .navigationBarTitleDisplayMode(.inline)
            .quickLookPreview($previewURL)
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    @Query(sort: \VaultItem.deletedAt, order: .reverse) private var items: [VaultItem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.filter { $0.deletedAt != nil }) { item in
                    VStack(alignment: .leading) {
                        Text(vaultStore.metadata(for: item)?.originalName ?? item.id)
                        Text(item.deletedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .swipeActions {
                        Button("Restore") {
                            Task { await vaultStore.restore(item, context: modelContext, sync: sync) }
                        }
                        .tint(AppTheme.primary)
                        Button("Delete Permanently", role: .destructive) {
                            Task {
                                await vaultStore.permanentlyDelete(item, context: modelContext, sync: sync)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trash")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MembershipView: View {
    @EnvironmentObject private var subscription: SubscriptionManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pro Private Vault")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                            Text("The free plan keeps local encryption and iCloud encrypted sync. Pro unlocks unlimited storage, batch organization, advanced disguise, decoy passcodes, intrusion records, and advanced recovery.")
                                .foregroundStyle(AppTheme.secondaryText)
                            StatusPill(title: subscription.statusText, systemImage: "star.circle", tint: subscription.isPro ? AppTheme.success : AppTheme.primary)
                        }
                    }

                    ForEach(subscription.products, id: \.id) { product in
                        AppCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.displayName)
                                        .font(.headline)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Button(product.displayPrice) {
                                    Task { await subscription.purchase(product) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.primary)
                            }
                        }
                    }

                    Button {
                        Task { await subscription.refreshEntitlements() }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    VStack(alignment: .leading, spacing: 8) {
                        FeatureLine("Save unlimited photos, videos, and files")
                        FeatureLine("Batch import and advanced organization")
                        FeatureLine("Disguised entry and decoy passcode space")
                        FeatureLine("Intrusion records and advanced trash recovery")
                        FeatureLine("Advanced trash recovery")
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Pro")
        }
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

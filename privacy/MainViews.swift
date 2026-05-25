import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var subscription: SubscriptionManager

    var body: some View {
        TabView {
            VaultHomeView()
                .tabItem { Label("Vault", systemImage: "lock.rectangle.stack") }
            ImportHubView()
                .tabItem { Label("Import", systemImage: "square.and.arrow.down") }
            SecurityCenterView()
                .tabItem { Label("Security", systemImage: "shield.lefthalf.filled") }
            MembershipView()
                .tabItem { Label("Pro", systemImage: "star.circle") }
        }
        .tint(AppTheme.primary)
        .task {
            await sync.checkAccountStatus()
            await vaultStore.bootstrap(context: modelContext, sync: sync)
            await ImportService.consumeSharedImports(context: modelContext, vaultStore: vaultStore, sync: sync)
            await vaultStore.pullCloudIndex(context: modelContext, sync: sync)
            await subscription.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                auth.lock()
            }
        }
        .onOpenURL { url in
            Task {
                if url.isFileURL {
                    await ImportService.importFile(url: url, context: modelContext, vaultStore: vaultStore, sync: sync, source: "Open In")
                } else {
                    await ImportService.importLink(url, source: "Open In", context: modelContext, vaultStore: vaultStore, sync: sync)
                }
            }
        }
        .background(AppTheme.background)
    }
}

struct VaultHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var items: [VaultItem]
    @Query(sort: \VaultFolder.sortOrder) private var folders: [VaultFolder]
    @State private var selectedItem: VaultItem?
    @State private var showTrash = false
    @State private var showCreateFolder = false
    @State private var selectedFolderId: String?

    private var activeItems: [VaultItem] { items.filter { $0.deletedAt == nil } }
    private var trashItems: [VaultItem] { items.filter { $0.deletedAt != nil } }
    private var activeFolders: [VaultFolder] { folders.filter { $0.deletedAt == nil } }
    private var visibleItems: [VaultItem] {
        activeItems.filter { item in
            selectedFolderId == nil || item.folderId == selectedFolderId
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Aegis Vault")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(L.format("%d encrypted assets", activeItems.count))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "lock.shield")
                                    .font(.title)
                                    .foregroundStyle(AppTheme.primary)
                            }
                            HStack {
                                StatusPill(title: L.string("Encrypted"), systemImage: "checkmark.shield", tint: AppTheme.success)
                                StatusPill(title: sync.state.title, systemImage: "icloud", tint: syncTint)
                            }
                            if let error = sync.lastSyncError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.warning)
                                    .lineLimit(2)
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        CategoryCard(title: L.string("Images"), count: activeItems.filter { $0.kind == .image }.count, icon: "photo")
                        CategoryCard(title: L.string("Videos"), count: activeItems.filter { $0.kind == .video }.count, icon: "video")
                        CategoryCard(title: L.string("Audio"), count: activeItems.filter { $0.kind == .audio }.count, icon: "waveform")
                        CategoryCard(title: L.string("Documents"), count: activeItems.filter { $0.kind == .document || $0.kind == .archive || $0.kind == .other }.count, icon: "doc")
                        CategoryCard(title: L.string("Links"), count: activeItems.filter { $0.kind == .link }.count, icon: "link")
                        Button {
                            showTrash = true
                        } label: {
                            CategoryCard(title: L.string("Trash"), count: trashItems.count, icon: "trash")
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Recent Imports")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Albums")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Button {
                                showCreateFolder = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                FolderChip(
                                    title: L.string("All"),
                                    count: activeItems.count,
                                    isSelected: selectedFolderId == nil
                                ) {
                                    selectedFolderId = nil
                                }

                                ForEach(activeFolders) { folder in
                                    FolderChip(
                                        title: vaultStore.folderName(folder),
                                        count: activeItems.filter { $0.folderId == folder.id }.count,
                                        isSelected: selectedFolderId == folder.id
                                    ) {
                                        selectedFolderId = folder.id
                                    }
                                }
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(visibleItems) { item in
                            VaultItemTile(item: item)
                                .onTapGesture { selectedItem = item }
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Vault")
            .sheet(item: $selectedItem) { item in
                VaultItemDetailView(item: item)
            }
            .sheet(isPresented: $showTrash) {
                TrashView()
            }
            .sheet(isPresented: $showCreateFolder) {
                FolderEditorView()
            }
            .refreshable {
                await ImportService.consumeSharedImports(context: modelContext, vaultStore: vaultStore, sync: sync)
                await vaultStore.pullCloudIndex(context: modelContext, sync: sync)
                await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
            }
        }
    }

    private var syncTint: Color {
        switch sync.state {
        case .synced, .available: AppTheme.success
        case .syncing, .checking: AppTheme.accent
        case .unavailable, .failed: AppTheme.warning
        }
    }
}

struct FolderChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : AppTheme.secondaryText)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : AppTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isSelected ? AppTheme.primary : AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? AppTheme.primary : AppTheme.line))
        }
        .buttonStyle(.plain)
    }
}

struct FolderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Album Name") {
                    TextField("e.g. IDs, contracts, private photos", text: $name)
                }
            }
            .navigationTitle("New Album")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await vaultStore.createFolder(named: name, context: modelContext, sync: sync)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct CategoryCard: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        AppCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(L.format("%d items", count))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
            }
        }
    }
}

struct VaultItemTile: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.card)
                .aspectRatio(1, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))

            if let image = vaultStore.thumbnail(for: item) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(AppTheme.primary)
                    Text(item.kind.rawValue.uppercased())
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(item.syncStatus == .synced ? AppTheme.success : AppTheme.warning)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
                Spacer()
            }
        }
    }

    private var icon: String {
        switch item.kind {
        case .image: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .document: "doc"
        case .archive: "archivebox"
        case .link: "link"
        case .other: "doc"
        }
    }
}

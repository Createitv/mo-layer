import PhotosUI
import SwiftData
import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var pendingSharedImports: [ImportService.PendingSharedImport] = []
    @State private var isImportingSharedFiles = false
    @State private var sharedImportMessage: String?

    var body: some View {
        VaultHomeView()
        .tint(AppTheme.primary)
        .task {
            await sync.checkAccountStatus()
            await vaultStore.bootstrap(context: modelContext, sync: sync)
            refreshPendingSharedImports()
            await vaultStore.pullCloudIndex(context: modelContext, sync: sync)
            await subscription.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                auth.lock()
            } else if phase == .active {
                refreshPendingSharedImports()
            }
        }
        .onOpenURL { url in
            Task {
                if url.scheme == "privacy" && url.host() == "shared-imports" {
                    refreshPendingSharedImports()
                } else if url.isFileURL {
                    if ImportService.stageFileForReview(url: url) {
                        refreshPendingSharedImports()
                    }
                } else {
                    await ImportService.importLink(url, source: "Open In", context: modelContext, vaultStore: vaultStore, sync: sync)
                }
            }
        }
        .sheet(isPresented: sharedImportSheetBinding) {
            SharedImportReviewSheet(
                imports: pendingSharedImports,
                isImporting: isImportingSharedFiles,
                message: sharedImportMessage,
                saveAction: { Task { await savePendingSharedImports() } },
                cancelAction: discardPendingSharedImports
            )
        }
        .background(AppTheme.background)
    }

    private var sharedImportSheetBinding: Binding<Bool> {
        Binding {
            !pendingSharedImports.isEmpty
        } set: { isPresented in
            if !isPresented, !isImportingSharedFiles {
                refreshPendingSharedImports()
            }
        }
    }

    @MainActor
    private func refreshPendingSharedImports() {
        pendingSharedImports = ImportService.pendingSharedImports()
        if pendingSharedImports.isEmpty {
            sharedImportMessage = nil
        }
    }

    @MainActor
    private func savePendingSharedImports() async {
        guard !isImportingSharedFiles else { return }
        isImportingSharedFiles = true
        sharedImportMessage = L.string("Encrypting and saving shared files...")
        let result = await ImportService.importPendingSharedImports(context: modelContext, vaultStore: vaultStore, sync: sync)
        pendingSharedImports = ImportService.pendingSharedImports()
        if result.failed == 0 {
            sharedImportMessage = nil
            pendingSharedImports = []
        } else {
            sharedImportMessage = L.string("Some files could not be saved. You can retry or cancel.")
        }
        isImportingSharedFiles = false
    }

    @MainActor
    private func discardPendingSharedImports() {
        guard !isImportingSharedFiles else { return }
        ImportService.discardSharedImports()
        pendingSharedImports = []
        sharedImportMessage = nil
    }
}

enum MainShellAction: String, CaseIterable {
    case profile
    case `import`
}

enum MainShellImportPresentation {
    case fullScreen
}

enum MainShellLayout {
    static let usesBottomTabBar = false
    static let trailingActions: [MainShellAction] = [.profile, .import]
    static let importPresentation: MainShellImportPresentation = .fullScreen
}

struct SharedImportReviewSheet: View {
    let imports: [ImportService.PendingSharedImport]
    let isImporting: Bool
    let message: String?
    let saveAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(imports) { item in
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: item))
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.primary)
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.primary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.originalName)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(L.string("Shared Files"))
                    } footer: {
                        Text(L.string("Files are encrypted on this device before they are uploaded to iCloud."))
                    }
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                VStack(spacing: 10) {
                    Button(action: saveAction) {
                        Label(isImporting ? L.string("Saving") : L.string("Save to Vault"), systemImage: "lock.doc")
                    }
                    .buttonStyle(AppButtonStyle())
                    .disabled(isImporting || imports.isEmpty)

                    Button(role: .destructive, action: cancelAction) {
                        Label(L.string("Cancel"), systemImage: "xmark")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isImporting)
                }
                .padding()
                .background(AppTheme.background)
            }
            .navigationTitle(L.string("Confirm Import"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func icon(for item: ImportService.PendingSharedImport) -> String {
        guard let type = UTType(item.typeIdentifier) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "video" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        return "doc"
    }
}

struct VaultHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var items: [VaultItem]
    @Query(sort: \VaultFolder.sortOrder) private var folders: [VaultFolder]
    @State private var selectedItem: VaultItem?
    @State private var previewSelection: MediaPreviewSelection?
    @State private var showProfileCenter = false
    @State private var showImportHub = false
    @State private var showCreateFolder = false
    @State private var selectedFolderId: String?
    @State private var importSummary: ImportSummary?
    @State private var mediaGridScale = MediaGridLayout.defaultScale

    private var activeItems: [VaultItem] { items.filter { $0.deletedAt == nil } }
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
                    VaultHomeHeader(
                        profileAction: { showProfileCenter = true },
                        importAction: { showImportHub = true }
                    )

                    GeometryReader { proxy in
                        let cardWidth = VaultCategoryCarouselLayout.cardWidth(
                            containerWidth: proxy.size.width,
                            categoryCount: VaultCategory.allCases.count
                        )

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: VaultCategoryCarouselLayout.spacing) {
                                ForEach(VaultCategory.allCases) { category in
                                    NavigationLink {
                                        VaultCategoryDetailView(
                                            category: category,
                                            items: category.items(from: items)
                                        )
                                    } label: {
                                        CategoryCard(
                                            title: category.title,
                                            count: category.items(from: items).count,
                                            icon: category.icon,
                                            category: category
                                        )
                                        .frame(width: cardWidth)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(height: VaultCategoryCarouselLayout.cardHeight)

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

                    ZoomableMediaGrid(items: visibleItems, scale: $mediaGridScale) { item in
                            VaultItemTile(item: item)
                                .onTapGesture { open(item, in: visibleItems) }
                                .contextMenu {
                                    Button {
                                        selectedItem = item
                                    } label: {
                                        Label(L.string("Details"), systemImage: "info.circle")
                                    }
                                }
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedItem) { item in
                VaultItemDetailView(item: item)
            }
            .fullScreenCover(item: $previewSelection) { selection in
                VaultMediaPreviewView(
                    items: selection.items,
                    initialItemId: selection.initialItemId
                )
            }
            .sheet(isPresented: $showCreateFolder) {
                FolderEditorView()
            }
            .fullScreenCover(isPresented: $showImportHub) {
                ImportHubView(showsCloseButton: true) { summary in
                    importSummary = summary
                    showImportHub = false
                }
            }
            .fullScreenCover(isPresented: $showProfileCenter) {
                ProfileCenterView()
            }
            .refreshable {
                await vaultStore.pullCloudIndex(context: modelContext, sync: sync)
                await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
            }
            .alert(item: $importSummary) { summary in
                Alert(
                    title: Text(summary.displayTitle),
                    message: Text(summary.displayMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func open(_ item: VaultItem, in collection: [VaultItem]) {
        guard item.kind.isPreviewableMedia else {
            selectedItem = item
            return
        }
        previewSelection = MediaPreviewSelection(
            items: collection.filter { $0.kind.isPreviewableMedia },
            initialItemId: item.id
        )
    }
}

enum VaultHomeHeaderLayout {
    static let actionSize: CGFloat = 34
    static let iconFontSize: CGFloat = 17
}

struct VaultHomeHeader: View {
    let profileAction: () -> Void
    let importAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("VAULT")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)

            Spacer()

            Button(action: profileAction) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: VaultHomeHeaderLayout.iconFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: VaultHomeHeaderLayout.actionSize, height: VaultHomeHeaderLayout.actionSize)
                    .background(AppTheme.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.string("Profile"))

            Button(action: importAction) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: VaultHomeHeaderLayout.iconFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: VaultHomeHeaderLayout.actionSize, height: VaultHomeHeaderLayout.actionSize)
                    .background(AppTheme.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.string("Import"))
        }
        .frame(minHeight: 44)
    }
}

struct ProfileCenterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SecurityCenterView()
                    } label: {
                        Label(L.string("Security Center"), systemImage: "shield.lefthalf.filled")
                    }

                    NavigationLink {
                        MembershipView()
                    } label: {
                        Label(L.string("Pro"), systemImage: "star.circle")
                    }
                }
            }
            .navigationTitle(L.string("Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.string("Close")) { dismiss() }
                }
            }
        }
    }
}

enum VaultCategoryCarouselLayout {
    static let spacing: CGFloat = 12
    static let cardHeight: CGFloat = 176
    static let visualHeight: CGFloat = 104
    static let iconFontSize: CGFloat = 40
    static let textAlignment: TextAlignment = .center

    static func cardWidth(containerWidth: CGFloat, categoryCount: Int) -> CGFloat {
        guard categoryCount > 0 else { return 0 }
        if categoryCount <= 3 {
            let totalSpacing = spacing * CGFloat(categoryCount - 1)
            return floor((containerWidth - totalSpacing) / CGFloat(categoryCount))
        }

        return min(158, max(132, floor(containerWidth * 0.223)))
    }
}

enum VaultCategory: String, CaseIterable, Identifiable {
    case images
    case videos
    case audio
    case documents
    case links

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: L.string("Images")
        case .videos: L.string("Videos")
        case .audio: L.string("Audio")
        case .documents: L.string("Documents")
        case .links: L.string("Links")
        }
    }

    var icon: String {
        switch self {
        case .images: "photo"
        case .videos: "video"
        case .audio: "waveform"
        case .documents: "doc"
        case .links: "link"
        }
    }

    func items(from items: [VaultItem]) -> [VaultItem] {
        items.filter { item in
            guard item.deletedAt == nil else { return false }
            switch self {
            case .images:
                return item.kind == .image
            case .videos:
                return item.kind == .video
            case .audio:
                return item.kind == .audio
            case .documents:
                return item.kind == .document || item.kind == .archive || item.kind == .other
            case .links:
                return item.kind == .link
            }
        }
    }
}

struct VaultCategoryDetailView: View {
    @State private var selectedItem: VaultItem?
    @State private var previewSelection: MediaPreviewSelection?
    @EnvironmentObject private var vaultStore: VaultStore
    let category: VaultCategory
    let items: [VaultItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        open(item)
                    } label: {
                        VaultCategoryItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(L.format("%d items", items.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(category.title, systemImage: category.icon, description: Text(L.string("No items yet")))
            }
        }
        .sheet(item: $selectedItem) { item in
            VaultItemDetailView(item: item)
        }
        .fullScreenCover(item: $previewSelection) { selection in
            VaultMediaPreviewView(
                items: selection.items,
                initialItemId: selection.initialItemId
            )
        }
    }

    private func open(_ item: VaultItem) {
        guard item.kind.isPreviewableMedia else {
            selectedItem = item
            return
        }
        previewSelection = MediaPreviewSelection(
            items: items.filter { $0.kind.isPreviewableMedia },
            initialItemId: item.id
        )
    }
}

private struct VaultCategoryItemRow: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    var body: some View {
        AppCard {
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(metadata?.originalName ?? L.string("Private Item"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusPill(title: item.syncStatus.title, systemImage: "icloud", tint: item.syncStatus == .failed ? AppTheme.warning : AppTheme.primary)
                        StatusPill(title: item.assetState.title, systemImage: item.assetState.systemImage, tint: item.assetState == .failed ? AppTheme.warning : AppTheme.success)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = vaultStore.thumbnail(for: item) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.primary.opacity(0.1))
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary)
            }
        }
    }

    private var detailText: String {
        let size = ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)
        let date = (metadata?.importedAt ?? item.createdAt).formatted(date: .abbreviated, time: .shortened)
        return "\(size) · \(date)"
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
    let category: VaultCategory

    var body: some View {
        AppCard {
            VStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(category.previewTint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: VaultCategoryCarouselLayout.iconFontSize, weight: .semibold))
                        .foregroundStyle(category.previewTint)
                }
                .frame(height: VaultCategoryCarouselLayout.visualHeight)
                .frame(maxWidth: .infinity)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(VaultCategoryCarouselLayout.textAlignment)
                    .minimumScaleFactor(0.78)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(VaultCategoryCarouselLayout.textAlignment)
            }
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .center)
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
                    if let badge = item.kind.previewBadgeSystemImage {
                        Image(systemName: badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.38))
                            .clipShape(Circle())
                            .padding(8)
                    }
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

struct MediaPreviewSelection: Identifiable {
    let id = UUID()
    let items: [VaultItem]
    let initialItemId: String
}

struct VaultMediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let items: [VaultItem]
    let initialItemId: String
    @State private var selectedId: String
    @State private var previewItems: [VaultItem]
    @State private var sharePayload: SharePayload?
    @State private var isPreparingShare = false

    init(items: [VaultItem], initialItemId: String) {
        self.items = items
        self.initialItemId = initialItemId
        _selectedId = State(initialValue: initialItemId)
        _previewItems = State(initialValue: items)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedId) {
                ForEach(previewItems) { item in
                    FullscreenMediaPage(item: item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.35))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Menu {
                        Button {
                            Task { await exportSelectedItem() }
                        } label: {
                            Label(L.string("Export"), systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            Task { await deleteSelectedItem() }
                        } label: {
                            Label(L.string("Delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(previewItems) { item in
                            Button {
                                selectedId = item.id
                            } label: {
                                MediaFilmstripThumb(item: item, isSelected: item.id == selectedId)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(.black.opacity(0.48))
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
    }

    private var selectedItem: VaultItem? {
        previewItems.first { $0.id == selectedId }
    }

    @MainActor
    private func exportSelectedItem() async {
        guard let selectedItem, !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        let urls = await vaultStore.decryptedTemporaryURLs(for: [selectedItem], context: modelContext, sync: sync)
        guard !urls.isEmpty else { return }
        sharePayload = SharePayload(items: urls)
    }

    @MainActor
    private func deleteSelectedItem() async {
        guard let selectedItem else { return }
        let nextSelection = previewItems.first { $0.id != selectedItem.id }?.id
        previewItems.removeAll { $0.id == selectedItem.id }
        await vaultStore.deleteImmediately(selectedItem, context: modelContext, sync: sync)
        if let nextSelection {
            selectedId = nextSelection
        } else {
            dismiss()
        }
    }
}

private struct FullscreenMediaPage: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if item.kind == .image, let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if item.kind == .video, let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if item.kind == .audio, let player {
                AudioPreviewPanel(player: player)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: item.kind.previewBadgeSystemImage ?? "doc")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .task(id: item.id) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let url = try? await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync) else { return }
        if item.kind == .image, let data = try? Data(contentsOf: url), let loaded = UIImage(data: data) {
            image = loaded
        } else if item.kind == .video || item.kind == .audio {
            player = AVPlayer(url: url)
        }
    }
}

private struct AudioPreviewPanel: View {
    let player: AVPlayer
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 86, weight: .semibold))
                .foregroundStyle(.white)

            Button {
                isPlaying.toggle()
                isPlaying ? player.play() : player.pause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            player.pause()
            isPlaying = false
        }
    }
}

private struct MediaFilmstripThumb: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = vaultStore.thumbnail(for: item) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.14))
                Image(systemName: item.kind.previewBadgeSystemImage ?? "doc")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Image(systemName: item.kind.previewBadgeSystemImage ?? "doc")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? .white : .clear, lineWidth: 2))
    }
}

extension VaultItemKind {
    var isPreviewableMedia: Bool {
        self == .image || self == .video || self == .audio
    }

    var isVisualMedia: Bool {
        self == .image || self == .video
    }

    var previewBadgeSystemImage: String? {
        switch self {
        case .image: "photo.fill"
        case .video: "video.fill"
        case .audio: "waveform"
        default: nil
        }
    }
}

private extension VaultCategory {
    var previewTint: Color {
        switch self {
        case .images: AppTheme.primary
        case .videos: AppTheme.accent
        case .audio: AppTheme.success
        case .documents: AppTheme.secondaryText
        case .links: AppTheme.warning
        }
    }
}

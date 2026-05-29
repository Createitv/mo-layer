import AVFoundation
import Photos
import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import AVKit
import OSLog
import UniformTypeIdentifiers
import Combine

struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var quickActions: QuickActionRouter
    @State private var pendingSharedImports: [ImportService.PendingSharedImport] = []
    @State private var isImportingSharedFiles = false
    @State private var sharedImportMessage: String?

    var body: some View {
        VaultHomeView()
        .tint(AppTheme.primary)
        .task {
            await subscription.load()
            await sync.checkAccountStatus()
            await vaultStore.bootstrap(context: modelContext, sync: sync, allowsCloudSync: subscription.canImportAndSync)
            refreshPendingSharedImports()
            if subscription.canImportAndSync {
                await vaultStore.pullCloudIndex(context: modelContext, sync: sync)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if auth.shouldLock(for: phase) {
                auth.lock()
            } else if phase == .active {
                refreshPendingSharedImports()
            }
        }
        .onOpenURL { url in
            Task {
                if url.scheme == "privacy" && url.host() == "shared-imports" {
                    await autoSavePendingSharedImports()
                } else if url.isFileURL {
                    if subscription.canImportAndSync, ImportService.stageFileForReview(url: url) {
                        refreshPendingSharedImports()
                    } else if !subscription.canImportAndSync {
                        sharedImportMessage = L.string("Renew Pro to import new files.")
                    }
                } else {
                    if subscription.canImportAndSync {
                        await ImportService.importLink(url, source: "Open In", context: modelContext, vaultStore: vaultStore, sync: sync)
                    } else {
                        sharedImportMessage = L.string("Renew Pro to import new links.")
                    }
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
        guard subscription.canImportAndSync else {
            sharedImportMessage = L.string("Renew Pro to import new files.")
            return
        }
        isImportingSharedFiles = true
        sharedImportMessage = L.string("Encrypting and saving shared files...")
        let result = await ImportService.importPendingSharedImports(context: modelContext, vaultStore: vaultStore, sync: sync)
        pendingSharedImports = ImportService.pendingSharedImports()
        if result.failedCount == 0 {
            sharedImportMessage = nil
            pendingSharedImports = []
            routeToImportedCategory(result)
        } else {
            sharedImportMessage = L.string("Some files could not be saved. You can retry or cancel.")
        }
        isImportingSharedFiles = false
    }

    @MainActor
    private func autoSavePendingSharedImports() async {
        guard !isImportingSharedFiles else { return }
        guard subscription.canImportAndSync else {
            refreshPendingSharedImports()
            sharedImportMessage = L.string("Renew Pro to import new files.")
            return
        }

        let pending = ImportService.pendingSharedImports()
        guard !pending.isEmpty else {
            pendingSharedImports = []
            sharedImportMessage = nil
            return
        }

        isImportingSharedFiles = true
        sharedImportMessage = L.string("Encrypting and saving shared files...")
        let result = await ImportService.importPendingSharedImports(context: modelContext, vaultStore: vaultStore, sync: sync)
        pendingSharedImports = ImportService.pendingSharedImports()
        if result.failedCount == 0 {
            sharedImportMessage = nil
            pendingSharedImports = []
            routeToImportedCategory(result)
        } else {
            sharedImportMessage = L.string("Some files could not be saved. You can retry or cancel.")
        }
        isImportingSharedFiles = false
    }

    @MainActor
    private func routeToImportedCategory(_ summary: ImportSummary) {
        guard let category = summary.preferredVaultCategory else { return }
        quickActions.route(to: category)
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
    @EnvironmentObject private var quickActions: QuickActionRouter
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var vaultStore: VaultStore
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var items: [VaultItem]
    @State private var selectedItem: VaultItem?
    @State private var previewSelection: MediaPreviewSelection?
    @State private var showProfileCenter = false
    @State private var showImportHub = false
    @State private var showQuickCamera = false
    @State private var showQuickRecorder = false
    @State private var showMembership = false
    @State private var selectedCategory: VaultCategory = .images
    @State private var importSummary: ImportSummary?
    @AppStorage(MediaGridScaleStorage.imagesKey) private var imageGridScale = MediaGridScaleStorage.defaultStoredScale
    @AppStorage(MediaGridScaleStorage.videosKey) private var videoGridScale = MediaGridScaleStorage.defaultStoredScale
    @AppStorage(MediaGridScaleStorage.audioKey) private var audioGridScale = MediaGridScaleStorage.defaultStoredScale
    @AppStorage(MediaGridScaleStorage.documentsKey) private var documentGridScale = MediaGridScaleStorage.defaultStoredScale

    private var activeItems: [VaultItem] { items.filter { $0.deletedAt == nil } }
    private var categoryItems: [VaultItem] {
        selectedCategory.items(from: activeItems)
    }
    private var visibleItems: [VaultItem] {
        categoryItems
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VaultHomeHeader(
                        selectedCategory: $selectedCategory,
                        profileAction: { showProfileCenter = true },
                        importAction: {
                            if subscription.canImportAndSync {
                                showImportHub = true
                            } else {
                                showMembership = true
                            }
                        }
                    )

                    if subscription.accessLevel == .expiredReadOnly {
                        ReadOnlyProtectionBanner()
                    }

                    ZStack(alignment: .top) {
                        ZoomableMediaGrid(items: visibleItems, scale: mediaGridScaleBinding) { item in
                            VaultItemTile(item: item)
                                .onTapGesture { open(item, in: visibleItems) }
                                .modifier(
                                    VaultItemLongPressAction(
                                        item: item,
                                        previewAction: { openPreview(item, in: visibleItems) },
                                        detailAction: { selectedItem = item }
                                    )
                                )
                        }

                        if visibleItems.isEmpty {
                            EmptyCategoryState(category: selectedCategory)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                                .allowsHitTesting(false)
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
            .fullScreenCover(isPresented: $showImportHub) {
                ImportHubView(showsCloseButton: true) { summary in
                    handleImportCompletion(summary)
                    showImportHub = false
                }
            }
            .fullScreenCover(isPresented: $showQuickCamera) {
                NativeCameraCaptureView { media in
                    guard subscription.canImportAndSync else { return }
                    Task {
                        let summary = await media.importSummary(
                            context: modelContext,
                            vaultStore: vaultStore,
                            sync: sync,
                            source: "Quick Camera"
                        )
                        handleImportCompletion(summary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showQuickRecorder) {
                AudioRecorderView { url, completion in
                    guard subscription.canImportAndSync else {
                        completion(false)
                        return
                    }
                    Task {
                        let summary = await ImportService.importFiles(
                            urls: [url],
                            context: modelContext,
                            vaultStore: vaultStore,
                            sync: sync,
                            source: "Quick Recorder"
                        )
                        try? FileManager.default.removeItem(at: url)
                        handleImportCompletion(summary)
                        completion(summary.importedCount > 0)
                    }
                }
            }
            .fullScreenCover(isPresented: $showProfileCenter) {
                ProfileCenterView()
            }
            .fullScreenCover(isPresented: $showMembership) {
                MembershipView(isRequiredBeforeUse: true)
            }
            .onAppear {
                handleQuickAction(quickActions.pendingAction)
            }
            .onChange(of: quickActions.pendingAction) { _, action in
                handleQuickAction(action)
            }
            .onAppear {
                handleCategoryRoute(quickActions.pendingCategory)
            }
            .onChange(of: quickActions.pendingCategory) { _, category in
                handleCategoryRoute(category)
            }
            .refreshable {
                guard subscription.canImportAndSync else { return }
                await vaultStore.pullCloudIndex(context: modelContext, sync: sync)
                await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
            }
            .alert(item: $importSummary) { summary in
                Alert(
                    title: Text(summary.displayTitle),
                    message: Text(summary.displayMessage),
                    dismissButton: .default(Text(L.string("OK")))
                )
            }
        }
    }

    private func handleImportCompletion(_ summary: ImportSummary) {
        if let category = summary.preferredVaultCategory {
            withAnimation(.snappy) {
                selectedCategory = category
            }
        }
        importSummary = summary
    }

    private func handleQuickAction(_ action: QuickAction?) {
        guard let action else { return }
        switch action {
        case .importHub:
            if subscription.canImportAndSync {
                showImportHub = true
            } else {
                showMembership = true
            }
        case .camera:
            if subscription.canImportAndSync {
                showQuickCamera = true
            } else {
                showMembership = true
            }
        case .recorder:
            if subscription.canImportAndSync {
                showQuickRecorder = true
            } else {
                showMembership = true
            }
        }
        quickActions.consume(action)
    }

    private func handleCategoryRoute(_ category: VaultCategory?) {
        guard let category else { return }
        withAnimation(.snappy) {
            selectedCategory = category
        }
        quickActions.consume(category)
    }

    private func open(_ item: VaultItem, in collection: [VaultItem]) {
        guard item.kind.isPreviewableContent else {
            selectedItem = item
            return
        }
        openPreview(item, in: collection)
    }

    private func openPreview(_ item: VaultItem, in collection: [VaultItem]) {
        guard item.kind.isPreviewableContent else { return }
        previewSelection = MediaPreviewSelection(
            items: collection.filter { $0.kind.isPreviewableContent },
            initialItemId: item.id
        )
    }

    private var mediaGridScaleBinding: Binding<CGFloat> {
        Binding {
            MediaGridLayout.persistedScale(storedScale(for: selectedCategory))
        } set: { value in
            setStoredScale(MediaGridLayout.storedScale(value), for: selectedCategory)
        }
    }

    private func storedScale(for category: VaultCategory) -> Double {
        switch category {
        case .images:
            imageGridScale
        case .videos:
            videoGridScale
        case .audio:
            audioGridScale
        case .documents, .links:
            documentGridScale
        }
    }

    private func setStoredScale(_ scale: Double, for category: VaultCategory) {
        switch category {
        case .images:
            imageGridScale = scale
        case .videos:
            videoGridScale = scale
        case .audio:
            audioGridScale = scale
        case .documents, .links:
            documentGridScale = scale
        }
    }
}

private struct ReadOnlyProtectionBanner: View {
    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.open.display")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.string("Read-Only Protection"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(L.string("Your saved local vault stays available. Renew Pro to import, back up, restore, and sync across devices."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EmptyCategoryState: View {
    let category: VaultCategory

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 64, height: 64)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))

            Text(L.string("No items yet"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}

enum VaultHomeHeaderLayout {
    static let actionSize: CGFloat = 34
    static let iconFontSize: CGFloat = 17
}

struct VaultHomeHeader: View {
    @Binding var selectedCategory: VaultCategory
    let profileAction: () -> Void
    let importAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: VaultHomeHeaderLayout.iconFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: VaultHomeHeaderLayout.actionSize, height: VaultHomeHeaderLayout.actionSize)
                    .background(AppTheme.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.string("Import"))
        }
        .frame(minHeight: 44)
    }
}

enum ProfileSettingsRoute: String, CaseIterable, Identifiable {
    case general
    case security
    case membership

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return L.string("General Settings")
        case .security:
            return L.string("Security Center")
        case .membership:
            return L.string("Pro")
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .security:
            return "shield.lefthalf.filled"
        case .membership:
            return "star.circle"
        }
    }
}

enum ProfileDocumentRoute: String, CaseIterable, Hashable {
    case privacyPolicy
    case permissions

    var title: String {
        switch self {
        case .privacyPolicy:
            L.string("Privacy Policy")
        case .permissions:
            L.string("User Permissions")
        }
    }
}

struct ProfileCenterView: View {
    @Environment(\.dismiss) private var dismiss
    private let accountRoutes: [ProfileSettingsRoute] = [.general, .security, .membership]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accountRoutes) { route in
                        NavigationLink {
                            profileDestination(for: route)
                        } label: {
                            Label(route.title, systemImage: route.systemImage)
                        }
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
            .safeAreaInset(edge: .bottom) {
                ProfileDocumentFooter()
            }
            .navigationDestination(for: ProfileDocumentRoute.self) { route in
                switch route {
                case .privacyPolicy:
                    PrivacyPolicyView()
                case .permissions:
                    UserPermissionsView()
                }
            }
        }
    }

    @ViewBuilder
    private func profileDestination(for route: ProfileSettingsRoute) -> some View {
        switch route {
        case .general:
            GeneralSettingsView()
        case .security:
            SecurityCenterView()
        case .membership:
            MembershipView()
        }
    }
}

private struct ProfileDocumentFooter: View {
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: ProfileDocumentRoute.privacyPolicy) {
                Text(ProfileDocumentRoute.privacyPolicy.title)
            }

            Text("·")
                .foregroundStyle(AppTheme.secondaryText.opacity(0.7))

            NavigationLink(value: ProfileDocumentRoute.permissions) {
                Text(ProfileDocumentRoute.permissions.title)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

enum VaultCategoryCarouselLayout {
    static let spacing: CGFloat = 10
    static let cardHeight: CGFloat = 132
    static let iconContainerSize: CGFloat = 48
    static let iconFontSize: CGFloat = 22
    static let contentMinHeight: CGFloat = 100
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

private extension ImportSummary {
    var preferredVaultCategory: VaultCategory? {
        let categoryScores = VaultCategory.homeModes.compactMap { category -> (category: VaultCategory, count: Int)? in
            let count = importedByKind.reduce(0) { partialResult, entry in
                category.contains(kind: entry.key) ? partialResult + entry.value : partialResult
            }
            return count > 0 ? (category, count) : nil
        }

        return categoryScores.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return VaultCategory.homeModes.firstIndex(of: lhs.category) ?? 0 < VaultCategory.homeModes.firstIndex(of: rhs.category) ?? 0
            }
            return lhs.count > rhs.count
        }.first?.category
    }
}

enum VaultCategory: String, CaseIterable, Identifiable {
    case images
    case videos
    case audio
    case documents
    case links

    var id: String { rawValue }
    static let homeModes: [VaultCategory] = [.images, .videos, .audio, .documents]

    var title: String {
        switch self {
        case .images: L.string("Photos")
        case .videos: L.string("Videos")
        case .audio: L.string("Audio")
        case .documents: L.string("Files")
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
            return contains(kind: item.kind)
        }
    }

    func contains(kind: VaultItemKind) -> Bool {
        switch self {
        case .images:
            return kind == .image || kind == .livePhoto
        case .videos:
            return kind == .video
        case .audio:
            return kind == .audio
        case .documents:
            return kind == .document || kind == .archive || kind == .other
        case .links:
            return kind == .link
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
                    .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 18) {
                        openLongPressPreview(item)
                    }
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
        guard item.kind.isPreviewableContent else {
            selectedItem = item
            return
        }
        openPreview(item)
    }

    private func openPreview(_ item: VaultItem) {
        guard item.kind.isPreviewableContent else { return }
        previewSelection = MediaPreviewSelection(
            items: items.filter { $0.kind.isPreviewableContent },
            initialItemId: item.id
        )
    }

    private func openLongPressPreview(_ item: VaultItem) {
        guard item.kind.usesLongPressMediaPreview else { return }
        openPreview(item)
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
        case .livePhoto: "livephoto"
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
            .background(isSelected ? AppTheme.primaryFill : AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? AppTheme.primaryFill : AppTheme.line))
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
                Section(L.string("Album Name")) {
                    TextField(L.string("e.g. IDs, contracts, private photos"), text: $name)
                }
            }
            .navigationTitle(L.string("New Album"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.string("Save")) {
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(category.previewTint.opacity(0.14))
                        Image(systemName: icon)
                            .font(.system(size: VaultCategoryCarouselLayout.iconFontSize, weight: .semibold))
                            .foregroundStyle(category.previewTint)
                    }
                    .frame(
                        width: VaultCategoryCarouselLayout.iconContainerSize,
                        height: VaultCategoryCarouselLayout.iconContainerSize
                    )

                    Spacer(minLength: 8)

                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(category.previewTint)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(category.previewTint.opacity(0.1))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(L.format("%d items", count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: VaultCategoryCarouselLayout.contentMinHeight,
                alignment: .topLeading
            )
        }
    }
}

struct VaultItemTile: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    @State private var livePhoto: PHLivePhoto?
    @State private var isLivePhotoPressed = false
    @State private var isLoadingLivePhoto = false

    var body: some View {
        GeometryReader { proxy in
            let tileSize = max(proxy.size.width, 1)
            let badgeSize = min(max(tileSize * 0.22, 14), 24)
            let badgePadding = min(max(tileSize * 0.055, 3), 8)
            let syncDotSize = min(max(tileSize * 0.075, 4), 8)
            let cornerRadius = min(max(tileSize * 0.08, 5), 8)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(AppTheme.line))

                if let image = vaultStore.thumbnail(for: item) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    VStack(spacing: min(max(tileSize * 0.055, 3), 8)) {
                        Image(systemName: icon)
                            .font(.system(size: min(max(tileSize * 0.22, 14), 28), weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                        if tileSize >= 72 {
                            Text(item.kind.rawValue.uppercased())
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }

                if item.kind == .livePhoto, isLivePhotoPressed, let livePhoto {
                    LivePhotoPlaybackView(livePhoto: livePhoto, playbackStyle: .full)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }

                MediaThumbnailOverlay(kind: item.kind, tileSize: tileSize, cornerRadius: cornerRadius)

                VStack {
                    HStack {
                        if !item.kind.isVisualMedia, let badge = item.kind.previewBadgeSystemImage {
                            Image(systemName: badge)
                                .font(.system(size: badgeSize * 0.52, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: badgeSize, height: badgeSize)
                                .background(.black.opacity(0.38))
                                .clipShape(Circle())
                                .padding(badgePadding)
                        }
                        Spacer()
                        Circle()
                            .fill(item.syncStatus == .synced ? AppTheme.success : AppTheme.warning)
                            .frame(width: syncDotSize, height: syncDotSize)
                            .padding(badgePadding)
                    }
                    Spacer()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .onLongPressGesture(
            minimumDuration: 0.25,
            maximumDistance: 18,
            pressing: { pressing in
                guard item.kind == .livePhoto else { return }
                isLivePhotoPressed = pressing
                if pressing {
                    loadLivePhotoIfNeeded()
                }
            },
            perform: {}
        )
    }

    private var icon: String {
        switch item.kind {
        case .image: "photo"
        case .livePhoto: "livephoto"
        case .video: "video"
        case .audio: "waveform"
        case .document: "doc"
        case .archive: "archivebox"
        case .link: "link"
        case .other: "doc"
        }
    }

    private func loadLivePhotoIfNeeded() {
        guard livePhoto == nil, !isLoadingLivePhoto else { return }
        isLoadingLivePhoto = true
        Task {
            let loaded = await makeLivePhoto(for: item, vaultStore: vaultStore, context: modelContext, sync: sync)
            await MainActor.run {
                livePhoto = loaded
                isLoadingLivePhoto = false
            }
        }
    }
}

private struct MediaThumbnailOverlay: View {
    let kind: VaultItemKind
    let tileSize: CGFloat
    let cornerRadius: CGFloat

    private var iconSize: CGFloat {
        min(max(tileSize * 0.14, 9), 18)
    }

    private var inset: CGFloat {
        min(max(tileSize * 0.055, 3), 8)
    }

    var body: some View {
        ZStack {
            if kind.isVisualMedia {
                LinearGradient(
                    colors: [.clear, .black.opacity(kind == .image ? 0.18 : 0.34)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }

            switch kind {
            case .livePhoto:
                VStack {
                    HStack {
                        Image(systemName: "livephoto")
                            .font(.system(size: iconSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                            .padding(inset)
                        Spacer()
                    }
                    Spacer()
                }
            case .video:
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: iconSize, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: iconSize * 1.75, height: iconSize * 1.75)
                            .background(.black.opacity(0.34))
                            .clipShape(Circle())
                            .padding(inset)
                        Spacer()
                    }
                }
            default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}

private struct LivePhotoPlaybackView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playbackStyle: PHLivePhotoViewPlaybackStyle?

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        if let playbackStyle {
            uiView.startPlayback(with: playbackStyle)
        } else {
            uiView.stopPlayback()
        }
    }
}

private func makeLivePhoto(
    for item: VaultItem,
    vaultStore: VaultStore,
    context: ModelContext,
    sync: CloudKitSyncService
) async -> PHLivePhoto? {
    guard item.kind == .livePhoto,
          let resourceURLs = try? await vaultStore.decryptedLivePhotoResourceURLs(for: item, context: context, sync: sync) else {
        return nil
    }

    return await withCheckedContinuation { continuation in
        PHLivePhoto.request(
            withResourceFileURLs: resourceURLs,
            placeholderImage: vaultStore.thumbnail(for: item),
            targetSize: .zero,
            contentMode: .aspectFill
        ) { livePhoto, _ in
            continuation.resume(returning: livePhoto)
        }
    }
}

struct MediaPreviewSelection: Identifiable {
    let id = UUID()
    let items: [VaultItem]
    let initialItemId: String
}

private struct VaultItemLongPressAction: ViewModifier {
    let item: VaultItem
    let previewAction: () -> Void
    let detailAction: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if item.kind.usesLongPressMediaPreview {
            content.onLongPressGesture(minimumDuration: 0.35, maximumDistance: 18) {
                previewAction()
            }
        } else {
            content.contextMenu {
                Button(action: detailAction) {
                    Label(L.string("Details"), systemImage: "info.circle")
                }
            }
        }
    }
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
    @State private var isSavingToPhotos = false
    @State private var photoSaveAlert: PhotoSaveAlert?

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
                    FullscreenMediaPage(item: item, isSelected: item.id == selectedId)
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

                    if canSaveSelectedItemToPhotos {
                        Button {
                            Task { await saveSelectedItemToPhotos() }
                        } label: {
                            Image(systemName: isSavingToPhotos ? "hourglass" : "square.and.arrow.down")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .disabled(isSavingToPhotos)
                    }

                    Menu {
                        if canSaveSelectedItemToPhotos {
                            Button {
                                Task { await saveSelectedItemToPhotos() }
                            } label: {
                                Label(
                                    isSavingToPhotos ? L.string("Saving to Photos") : L.string("Save to Photos"),
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                            .disabled(isSavingToPhotos)
                        }

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
        .alert(item: $photoSaveAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L.string("OK")))
            )
        }
        .onAppear {
            MediaPreviewAudioSession.activateForPlayback()
        }
        .onDisappear {
            MediaPreviewAudioSession.deactivate()
        }
    }

    private var selectedItem: VaultItem? {
        previewItems.first { $0.id == selectedId }
    }

    private var canSaveSelectedItemToPhotos: Bool {
        selectedItem.map { PhotoLibraryExportService.canSaveToPhotoLibrary(kind: $0.kind) } ?? false
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
    private func saveSelectedItemToPhotos() async {
        guard let selectedItem, !isSavingToPhotos else { return }
        isSavingToPhotos = true
        let result = await PhotoLibraryExportService.save(
            item: selectedItem,
            vaultStore: vaultStore,
            context: modelContext,
            sync: sync
        )
        isSavingToPhotos = false
        photoSaveAlert = PhotoSaveAlert(result: result)
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

private struct PhotoSaveAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(result: PhotoLibraryExportResult) {
        self.title = result.title
        self.message = result.message
    }
}

private enum MediaPreviewAudioSession {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "MediaPreviewAudio")

    static func activateForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            logger.error("Media preview audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Media preview audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func configure(_ player: AVPlayer) {
        player.isMuted = false
        player.volume = 1
    }
}

private struct FullscreenMediaPage: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "MediaPreview")
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    let isSelected: Bool
    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var player: AVPlayer?
    @State private var previewURL: URL?
    @State private var previewTitle = ""
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if item.kind == .livePhoto, let livePhoto {
                LivePhotoPlaybackView(livePhoto: livePhoto, playbackStyle: isSelected ? .hint : nil)
                    .ignoresSafeArea()
            } else if item.kind == .image, let image {
                ZoomableImagePreview(image: image)
            } else if item.kind == .video, let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { updateVideoPlayback() }
                    .onChange(of: isSelected) { _, _ in updateVideoPlayback() }
                    .onDisappear { player.pause() }
            } else if item.kind == .audio, let player {
                AudioPreviewPanel(title: previewTitle, player: player)
            } else if item.kind.isDocumentPreview, let previewURL {
                DocumentPreviewContainer(url: previewURL)
                    .ignoresSafeArea()
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                UnsupportedPreviewState(kind: item.kind)
            }
        }
        .task(id: item.id) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        image = nil
        livePhoto = nil
        player?.pause()
        player = nil
        previewURL = nil
        previewTitle = vaultStore.metadata(for: item)?.originalName ?? L.string("Private Item")
        defer { isLoading = false }
        let url: URL
        do {
            url = try await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
        } catch {
            Self.logger.error("Preview decrypt failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        if item.kind == .livePhoto {
            livePhoto = await makeLivePhoto(for: item, vaultStore: vaultStore, context: modelContext, sync: sync)
        } else if item.kind == .image, let data = try? Data(contentsOf: url), let loaded = UIImage(data: data) {
            image = loaded
        } else if item.kind == .video || item.kind == .audio {
            let mediaPlayer = AVPlayer(url: url)
            MediaPreviewAudioSession.configure(mediaPlayer)
            player = mediaPlayer
            updateVideoPlayback(for: mediaPlayer)
        } else if item.kind.isDocumentPreview {
            previewURL = url
        } else {
            Self.logger.error("Preview data could not decode for item \(item.id, privacy: .public), kind \(item.kind.rawValue, privacy: .public)")
        }
    }

    private func updateVideoPlayback(for mediaPlayer: AVPlayer? = nil) {
        guard item.kind == .video else { return }
        let currentPlayer = mediaPlayer ?? player
        guard let currentPlayer else { return }
        MediaPreviewAudioSession.configure(currentPlayer)
        if isSelected {
            MediaPreviewAudioSession.activateForPlayback()
            currentPlayer.play()
        } else {
            currentPlayer.pause()
        }
    }
}

private struct ZoomableImagePreview: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    private var displayScale: CGFloat {
        clampedScale(scale * pinchScale)
    }

    var body: some View {
        GeometryReader { proxy in
            let offset = clampedOffset(
                CGSize(
                    width: committedOffset.width + dragTranslation.width,
                    height: committedOffset.height + dragTranslation.height
                ),
                scale: displayScale,
                containerSize: proxy.size
            )

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(displayScale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(zoomGesture(containerSize: proxy.size))
                .simultaneousGesture(dragGesture(containerSize: proxy.size))
                .onTapGesture(count: 2) {
                    withAnimation(.snappy(duration: 0.2)) {
                        if scale > 1 {
                            scale = 1
                            committedOffset = .zero
                        } else {
                            scale = 2.5
                        }
                    }
                }
        }
    }

    private func zoomGesture(containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                withAnimation(.snappy(duration: 0.18)) {
                    scale = clampedScale(scale * value)
                    committedOffset = clampedOffset(
                        committedOffset,
                        scale: scale,
                        containerSize: containerSize
                    )
                }
            }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                guard displayScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > 1 else {
                    committedOffset = .zero
                    return
                }
                committedOffset = clampedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    scale: scale,
                    containerSize: containerSize
                )
            }
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 5)
    }

    private func clampedOffset(_ value: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let maxX = containerSize.width * (scale - 1) / 2
        let maxY = containerSize.height * (scale - 1) / 2
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }
}

private struct DocumentPreviewContainer: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.view.backgroundColor = .systemBackground
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct UnsupportedPreviewState: View {
    let kind: VaultItemKind

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: kind.previewBadgeSystemImage ?? "doc")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(L.string("Preview unavailable"))
                .font(.headline)
                .foregroundStyle(.white)
            Text(L.string("Export this item to open it in another app."))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

private struct AudioPreviewPanel: View {
    let title: String
    let player: AVPlayer
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false

    private let progressTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 86, weight: .semibold))
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(L.string("Audio Preview"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
            }
            .padding(.horizontal, 32)

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { currentTime = $0 }
                    ),
                    in: 0...max(duration, 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                        }
                    }
                )
                .tint(.white)

                HStack {
                    Text(formattedTime(currentTime))
                    Spacer()
                    Text(formattedTime(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, 36)

            Button {
                if isPlaying {
                    player.pause()
                    isPlaying = false
                } else {
                    MediaPreviewAudioSession.activateForPlayback()
                    MediaPreviewAudioSession.configure(player)
                    player.play()
                    isPlaying = true
                }
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
        .onAppear {
            MediaPreviewAudioSession.configure(player)
            refreshProgress()
        }
        .onReceive(progressTimer) { _ in
            refreshProgress()
        }
        .onDisappear {
            player.pause()
            isPlaying = false
        }
    }

    private func refreshProgress() {
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite,
           itemDuration > 0 {
            duration = itemDuration
        }
        guard !isScrubbing else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            currentTime = min(max(seconds, 0), max(duration, 0))
        }
        isPlaying = player.timeControlStatus == .playing
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
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
    var isPreviewableContent: Bool {
        switch self {
        case .image, .livePhoto, .video, .audio, .document, .archive, .other:
            true
        case .link:
            false
        }
    }

    var isPreviewableMedia: Bool {
        self == .image || self == .livePhoto || self == .video || self == .audio
    }

    var isDocumentPreview: Bool {
        self == .document || self == .archive || self == .other
    }

    var isVisualMedia: Bool {
        self == .image || self == .livePhoto || self == .video
    }

    var usesLongPressMediaPreview: Bool {
        self == .image || self == .video
    }

    var previewBadgeSystemImage: String? {
        switch self {
        case .image: "photo.fill"
        case .livePhoto: "livephoto"
        case .video: "video.fill"
        case .audio: "waveform"
        case .document: "doc.richtext"
        case .archive: "archivebox.fill"
        case .other: "doc"
        case .link: "link"
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

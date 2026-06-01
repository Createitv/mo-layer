import AVFoundation
import ImageIO
import MarkdownUI
import Photos
import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import AVKit
import OSLog
import UniformTypeIdentifiers
import Combine
import UIKit

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
            vaultStore.setWriteAccess(subscription.canImportAndSync)
            await sync.checkAccountStatus()
            await sync.ensureChangeSubscriptions()
            await vaultStore.bootstrap(context: modelContext, sync: sync, allowsCloudSync: subscription.canImportAndSync)
            refreshPendingSharedImports()
            await vaultStore.syncCloudToLocal(
                context: modelContext,
                sync: sync,
                allowsCloudSync: subscription.canImportAndSync
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if auth.shouldLock(for: phase) {
                auth.lock()
            } else if phase == .active {
                vaultStore.setWriteAccess(subscription.canImportAndSync)
                refreshPendingSharedImports()
                Task {
                    await vaultStore.syncCloudToLocal(
                        context: modelContext,
                        sync: sync,
                        allowsCloudSync: subscription.canImportAndSync
                    )
                }
            }
        }
        .onChange(of: subscription.canImportAndSync) { _, canWrite in
            vaultStore.setWriteAccess(canWrite)
        }
        .onOpenURL { url in
            Task {
                if url.scheme == "privacy" && url.host() == "shared-imports" {
                    await presentPendingSharedImportsFromExtension()
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
    private func presentPendingSharedImportsFromExtension() async {
        refreshPendingSharedImports()
        guard !pendingSharedImports.isEmpty else { return }
        if subscription.canImportAndSync {
            sharedImportMessage = L.string("Review these shared files. Photos, videos, audio, and files will be saved into their matching vault sections.")
        } else {
            sharedImportMessage = L.string("Renew Pro to import new files.")
        }
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
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var quickActions: QuickActionRouter
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var importQueue: VaultImportQueue
    @EnvironmentObject private var remoteChanges: CloudSyncRemoteChangeRouter
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var items: [VaultItem]
    @State private var selectedItem: VaultItem?
    @State private var previewSelection: MediaPreviewSelection?
    @State private var audioDetailItem: VaultItem?
    @State private var documentDetailItem: VaultItem?
    @State private var showProfileCenter = false
    @State private var showImportHub = false
    @State private var showQuickCamera = false
    @State private var showQuickRecorder = false
    @State private var showMembership = false
    @State private var selectedCategory: VaultCategory = .images
    @State private var importSummary: ImportSummary?
    @State private var selectionMode = false
    @State private var selectedItemIds: Set<String> = []
    @State private var confirmBulkDelete = false
    @State private var isDeletingSelection = false
    @State private var isInnerVaultActive = false
    @State private var sweepSelectionAnchorId: String?
    @State private var mediaGridItemFrames: [AnyHashable: CGRect] = [:]
    @State private var peekItem: VaultItem?
    @State private var peekTouchItemId: String?
    @State private var peekTask: Task<Void, Never>?
    @State private var suppressTapUntil: Date?
    @AppStorage(MediaGridScaleStorage.imagesKey) private var imageGridScale = MediaGridScaleStorage.defaultStoredScale
    @AppStorage(MediaGridScaleStorage.videosKey) private var videoGridScale = MediaGridScaleStorage.defaultStoredScale
    @AppStorage(MediaGridScaleStorage.audioKey) private var audioGridScale = MediaGridScaleStorage.defaultStoredScale
    @AppStorage(MediaGridScaleStorage.documentsKey) private var documentGridScale = MediaGridScaleStorage.defaultStoredScale

    private var activeItems: [VaultItem] { items.filter { $0.deletedAt == nil } }
    private var spaceItems: [VaultItem] {
        activeItems.filter { item in
            isInnerVaultActive ? item.folderId == VaultStore.innerVaultFolderId : item.folderId != VaultStore.innerVaultFolderId
        }
    }
    private var categoryItems: [VaultItem] {
        selectedCategory.items(from: spaceItems)
    }
    private var visibleItems: [VaultItem] {
        categoryItems
    }
    private var importDestinationFolderId: String? {
        isInnerVaultActive ? VaultStore.innerVaultFolderId : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                scrollContent
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                bottomInsetContent
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if let peekItem {
                    VaultPeekPreviewOverlay(item: peekItem)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .sheet(item: $selectedItem) { item in
                VaultItemDetailView(item: item)
            }
            .fullScreenCover(item: $audioDetailItem) { item in
                AudioDetailPlayerView(item: item)
            }
            .fullScreenCover(item: $documentDetailItem) { item in
                DocumentDetailPreviewView(item: item)
            }
            .fullScreenCover(item: $previewSelection) { selection in
                VaultMediaPreviewView(
                    items: selection.items,
                    initialItemId: selection.initialItemId
                )
            }
            .fullScreenCover(isPresented: $showImportHub) {
                ImportHubView(showsCloseButton: true, destinationFolderId: importDestinationFolderId) { summary in
                    handleImportCompletion(summary)
                    showImportHub = false
                }
                .environmentObject(subscription)
                .environmentObject(sync)
                .environmentObject(vaultStore)
                .environmentObject(importQueue)
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
                    .environmentObject(auth)
                    .environmentObject(subscription)
                    .environmentObject(sync)
                    .environmentObject(vaultStore)
                    .environmentObject(remoteChanges)
            }
            .fullScreenCover(isPresented: $showMembership) {
                MembershipView(isRequiredBeforeUse: true)
                    .environmentObject(subscription)
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
            .onChange(of: selectedCategory) { _, _ in
                clearSelection()
                endLightPeek()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                exitInnerVault()
            }
            .refreshable {
                await vaultStore.syncCloudToLocal(
                    context: modelContext,
                    sync: sync,
                    allowsCloudSync: subscription.canImportAndSync,
                    downloadsOriginals: VaultCloudToLocalSyncPolicy.pullToRefreshDownloadsOriginals
                )
            }
            .alert(item: $importSummary) { summary in
                Alert(
                    title: Text(summary.displayTitle),
                    message: Text(summary.displayMessage),
                    dismissButton: .default(Text(L.string("OK")))
                )
            }
            .alert(L.string("Delete Selected Items?"), isPresented: $confirmBulkDelete) {
                Button(L.string("Cancel"), role: .cancel) {}
                Button(L.string("Delete"), role: .destructive) {
                    Task { await deleteSelectedItems() }
                }
            } message: {
                Text(L.format("%d selected item(s) will be removed from this device and marked for removal from iCloud.", selectedItemIds.count))
            }
        }
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VaultHomeHeader(
                selectedCategory: $selectedCategory,
                isInnerVaultActive: isInnerVaultActive,
                profileAction: { showProfileCenter = true },
                importAction: openImportHub,
                toggleInnerVaultAction: toggleInnerVault
            )

            if !subscription.canImportAndSync {
                ReadOnlyProtectionBanner()
            }

            if let progress = importQueue.progress {
                VaultImportProgressBanner(progress: progress)
            }

            ZStack(alignment: .top) {
                categoryContent

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

    @ViewBuilder
    private var categoryContent: some View {
        if selectedCategory.usesListLayout {
            VaultLinearCategoryList(
                category: selectedCategory,
                items: visibleItems,
                openAudio: { audioDetailItem = $0 },
                openDocument: { documentDetailItem = $0 },
                openDetails: { selectedItem = $0 },
                deleteItem: { item in
                    Task { await delete(item) }
                }
            )
        } else {
            mediaGridContent
        }
    }

    private var mediaGridContent: some View {
        ZoomableMediaGrid(
            items: visibleItems,
            scale: mediaGridScaleBinding
        ) { item in
            mediaGridTile(for: item)
        }
        .onPreferenceChange(MediaGridItemFramePreferenceKey.self) { frames in
            mediaGridItemFrames = frames
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(MediaGridLayout.coordinateSpaceName))
                .onChanged { value in
                    handleSweepSelectionDrag(location: value.location, itemFrames: mediaGridItemFrames)
                }
                .onEnded { _ in
                    endSweepSelection()
                }
        )
    }

    private func mediaGridTile(for item: VaultItem) -> some View {
        SelectableVaultItemTile(
            item: item,
            isSelectionMode: selectionMode,
            isSelected: selectedItemIds.contains(item.id)
        )
        .onTapGesture {
            if shouldSuppressTap() {
                return
            }
            if selectionMode {
                toggleSelection(item)
            } else {
                open(item, in: visibleItems)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if abs(value.translation.width) + abs(value.translation.height) > 10 {
                        endLightPeek(for: item)
                    } else {
                        beginLightPeek(for: item)
                    }
                }
                .onEnded { _ in
                    endLightPeek(for: item)
                }
        )
        .modifier(
            VaultItemPressureSelectionAction(
                item: item,
                forceAction: {
                    guard subscription.canImportAndSync else { return }
                    enterSelectionMode(selecting: item)
                },
                fallbackLongPressAction: {
                    guard subscription.canImportAndSync else { return }
                    enterSelectionMode(selecting: item)
                }
            )
        )
        .modifier(
            VaultItemLongPressAction(
                item: item,
                previewAction: { openPreview(item, in: visibleItems) },
                detailAction: { selectedItem = item },
                isEnabled: !selectionMode
            )
        )
    }

    private var bottomInsetContent: some View {
        VStack(spacing: 8) {
            if selectionMode {
                VaultSelectionToolbar(
                    selectedCount: selectedItemIds.count,
                    isDeleting: isDeletingSelection,
                    canDelete: subscription.canImportAndSync,
                    moveTitle: subscription.canImportAndSync ? (isInnerVaultActive ? L.string("Restore") : L.string("Hide")) : nil,
                    moveSystemImage: isInnerVaultActive ? "arrow.uturn.left" : "lock.fill",
                    cancelAction: clearSelection,
                    moveAction: { Task { await moveSelectedItemsBetweenSpaces() } },
                    deleteAction: { confirmBulkDelete = true }
                )
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VaultCategorySummaryFooter(category: selectedCategory, count: visibleItems.count)
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

    private func openImportHub() {
        guard subscription.canImportAndSync else {
            showMembership = true
            return
        }

        guard isInnerVaultActive else {
            showImportHub = true
            return
        }

        Task { @MainActor in
            guard await vaultStore.ensureInnerVaultFolder(context: modelContext, sync: sync) != nil else { return }
            showImportHub = true
        }
    }

    private func enterInnerVault() {
        guard subscription.canImportAndSync else {
            showMembership = true
            return
        }

        Task { @MainActor in
            guard await vaultStore.ensureInnerVaultFolder(context: modelContext, sync: sync) != nil else { return }
            withAnimation(.snappy) {
                clearSelection()
                endLightPeek()
                isInnerVaultActive = true
            }
        }
    }

    private func toggleInnerVault() {
        if isInnerVaultActive {
            exitInnerVault()
        } else {
            enterInnerVault()
        }
    }

    private func exitInnerVault() {
        guard isInnerVaultActive else { return }
        withAnimation(.snappy) {
            clearSelection()
            endLightPeek()
            isInnerVaultActive = false
        }
    }

    private func handleQuickAction(_ action: QuickAction?) {
        guard let action else { return }
        switch action {
        case .importHub:
            openImportHub()
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

    private func enterSelectionMode(selecting item: VaultItem) {
        guard item.kind.isVisualMedia else { return }
        endLightPeek()
        withAnimation(.snappy) {
            selectionMode = true
            selectedItemIds.insert(item.id)
        }
    }

    private func toggleSelection(_ item: VaultItem) {
        guard item.kind.isVisualMedia else { return }
        withAnimation(.snappy) {
            if selectedItemIds.contains(item.id) {
                selectedItemIds.remove(item.id)
            } else {
                selectedItemIds.insert(item.id)
            }
            if selectedItemIds.isEmpty {
                selectionMode = false
            }
        }
    }

    private func clearSelection() {
        withAnimation(.snappy) {
            selectedItemIds.removeAll()
            selectionMode = false
            sweepSelectionAnchorId = nil
        }
    }

    private func handleSweepSelectionDrag(location: CGPoint, itemFrames: [AnyHashable: CGRect]) {
        guard selectionMode, subscription.canImportAndSync else { return }
        let selectableItems = visibleItems.filter { $0.kind.isVisualMedia }
        guard !selectableItems.isEmpty else { return }

        let currentItemId = selectableItems.first { item in
            itemFrames[AnyHashable(item.id)]?.insetBy(dx: -8, dy: -8).contains(location) == true
        }?.id

        if sweepSelectionAnchorId == nil {
            guard let currentItemId else { return }
            sweepSelectionAnchorId = currentItemId
            selectedItemIds.insert(currentItemId)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        guard let anchorId = sweepSelectionAnchorId,
              let anchorFrame = itemFrames[AnyHashable(anchorId)] else {
            return
        }

        let anchorPoint = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        let sweepRect = CGRect(
            x: min(anchorPoint.x, location.x),
            y: min(anchorPoint.y, location.y),
            width: abs(anchorPoint.x - location.x),
            height: abs(anchorPoint.y - location.y)
        )
        .insetBy(dx: -MediaGridLayout.spacing * 2, dy: -MediaGridLayout.spacing * 2)

        let sweptIds = selectableItems.compactMap { item -> String? in
            guard let frame = itemFrames[AnyHashable(item.id)],
                  frame.intersects(sweepRect) else {
                return nil
            }
            return item.id
        }
        guard !sweptIds.isEmpty else { return }

        let previousCount = selectedItemIds.count
        withAnimation(.snappy) {
            selectedItemIds.formUnion(sweptIds)
        }
        if selectedItemIds.count != previousCount {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func endSweepSelection() {
        sweepSelectionAnchorId = nil
    }

    private func shouldSuppressTap() -> Bool {
        guard let suppressTapUntil else { return false }
        return Date() < suppressTapUntil
    }

    private func beginLightPeek(for item: VaultItem) {
        guard !selectionMode,
              item.kind.isVisualMedia,
              peekTouchItemId != item.id else {
            return
        }
        peekTask?.cancel()
        peekTouchItemId = item.id
        peekTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled,
                  peekTouchItemId == item.id,
                  !selectionMode else {
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                peekItem = item
            }
        }
    }

    private func endLightPeek(for item: VaultItem? = nil) {
        if let item, peekTouchItemId != item.id {
            return
        }
        peekTask?.cancel()
        peekTask = nil
        peekTouchItemId = nil
        if peekItem != nil {
            suppressTapUntil = Date().addingTimeInterval(0.28)
        }
        withAnimation(.easeIn(duration: 0.10)) {
            peekItem = nil
        }
    }

    @MainActor
    private func delete(_ item: VaultItem) async {
        guard subscription.canImportAndSync else {
            showMembership = true
            return
        }
        await vaultStore.deleteImmediately(item, context: modelContext, sync: sync)
    }

    @MainActor
    private func deleteSelectedItems() async {
        guard subscription.canImportAndSync else {
            showMembership = true
            return
        }
        guard !selectedItemIds.isEmpty else { return }
        isDeletingSelection = true
        let ids = selectedItemIds
        let selectedItems = visibleItems.filter { ids.contains($0.id) }
        await vaultStore.deleteImmediately(selectedItems, context: modelContext, sync: sync)
        isDeletingSelection = false
        clearSelection()
    }

    @MainActor
    private func moveSelectedItemsBetweenSpaces() async {
        guard subscription.canImportAndSync else {
            showMembership = true
            return
        }
        guard !selectedItemIds.isEmpty else { return }
        let ids = selectedItemIds
        let selectedItems = visibleItems.filter { ids.contains($0.id) }
        if isInnerVaultActive {
            await vaultStore.moveOutOfInnerVault(selectedItems, context: modelContext, sync: sync)
        } else {
            await vaultStore.moveToInnerVault(selectedItems, context: modelContext, sync: sync)
        }
        clearSelection()
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
                    Text(L.string("Your existing vault is available in read-only mode. Renew Pro only when you want to add, edit, delete, or upload new backups."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VaultImportProgressBanner: View {
    let progress: VaultImportProgress

    var body: some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primary.opacity(0.12))
                    if progress.isActive {
                        ProgressView()
                            .scaleEffect(0.72)
                            .tint(AppTheme.primary)
                    } else {
                        Image(systemName: progress.failedCount > 0 ? "exclamationmark.icloud" : "checkmark.icloud")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(progress.failedCount > 0 ? AppTheme.warning : AppTheme.success)
                    }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.isActive ? L.string("Importing in Background") : L.string("Import Complete"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(progress.statusText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                    if !progress.isActive && progress.importedCount > 0 {
                        Text(L.string("iCloud backup will continue automatically."))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Spacer(minLength: 0)
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
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var remoteChanges: CloudSyncRemoteChangeRouter
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    private let accountRoutes: [ProfileSettingsRoute] = [.general, .security, .membership]

    private var preferenceRefreshToken: SettingsPreferenceRefreshToken {
        SettingsPreferenceRefreshToken(language: language, appearance: appearance)
    }

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
            .id(preferenceRefreshToken)
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
                .environmentObject(auth)
                .environmentObject(subscription)
                .environmentObject(sync)
        case .security:
            SecurityCenterView()
                .environmentObject(auth)
                .environmentObject(subscription)
                .environmentObject(sync)
                .environmentObject(vaultStore)
                .environmentObject(remoteChanges)
        case .membership:
            MembershipView()
                .environmentObject(subscription)
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

    func summaryText(count: Int) -> String {
        switch self {
        case .images:
            return L.format("Total %d photos", count)
        case .videos:
            return L.format("Total %d videos", count)
        case .audio:
            return L.format("Total %d audio files", count)
        case .documents:
            return L.format("Total %d files", count)
        case .links:
            return L.format("%d items", count)
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

private struct VaultCategorySummaryFooter: View {
    let category: VaultCategory
    let count: Int

    var body: some View {
        Text(category.summaryText(count: count))
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText.opacity(0.68))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(AppTheme.background.opacity(0.94))
    }
}

struct VaultCategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var selectedItem: VaultItem?
    @State private var previewSelection: MediaPreviewSelection?
    @State private var audioDetailItem: VaultItem?
    @State private var documentDetailItem: VaultItem?
    @EnvironmentObject private var vaultStore: VaultStore
    let category: VaultCategory
    let items: [VaultItem]

    var body: some View {
        ScrollView {
            if category.usesListLayout {
                VaultLinearCategoryList(
                    category: category,
                    items: items,
                    openAudio: { audioDetailItem = $0 },
                    openDocument: { documentDetailItem = $0 },
                    openDetails: { selectedItem = $0 },
                    deleteItem: { item in
                        Task { await delete(item) }
                    }
                )
                .padding()
            } else {
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
        }
        .background(AppTheme.background)
        .safeAreaInset(edge: .bottom) {
            VaultCategorySummaryFooter(category: category, count: items.count)
        }
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
        .fullScreenCover(item: $audioDetailItem) { item in
            AudioDetailPlayerView(item: item)
        }
        .fullScreenCover(item: $documentDetailItem) { item in
            DocumentDetailPreviewView(item: item)
        }
        .fullScreenCover(item: $previewSelection) { selection in
            VaultMediaPreviewView(
                items: selection.items,
                initialItemId: selection.initialItemId
            )
        }
        .refreshable {
            await vaultStore.syncCloudToLocal(
                context: modelContext,
                sync: sync,
                allowsCloudSync: subscription.canImportAndSync,
                downloadsOriginals: VaultCloudToLocalSyncPolicy.pullToRefreshDownloadsOriginals
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

    @MainActor
    private func delete(_ item: VaultItem) async {
        guard subscription.canImportAndSync else { return }
        await vaultStore.deleteImmediately(item, context: modelContext, sync: sync)
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

private struct VaultLinearCategoryList: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    let category: VaultCategory
    let items: [VaultItem]
    let openAudio: (VaultItem) -> Void
    let openDocument: (VaultItem) -> Void
    let openDetails: (VaultItem) -> Void
    let deleteItem: (VaultItem) -> Void
    @State private var activeAudioId: String?
    @State private var loadingAudioId: String?
    @State private var player: AVPlayer?
    @State private var activeAudioSamples: [CGFloat] = AudioWaveformAnalyzer.placeholderSamples
    @State private var audioCurrentTime: Double = 0
    @State private var audioDuration: Double = 0
    @State private var audioTimeObserver: Any?
    @State private var sharePayload: SharePayload?
    @State private var renameItem: VaultItem?

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(items) { item in
                if item.kind == .audio {
                    AudioListRow(
                        item: item,
                        isPlaying: activeAudioId == item.id,
                        isLoading: loadingAudioId == item.id,
                        waveformSamples: activeAudioId == item.id ? activeAudioSamples : [],
                        currentTime: activeAudioId == item.id ? audioCurrentTime : 0,
                        duration: activeAudioId == item.id ? audioDuration : 0,
                        playAction: { Task { await toggleAudioPlayback(item) } },
                        seekAction: { progress in seekActiveAudio(to: progress) },
                        openAction: {
                            stopAudioPlayback()
                            openAudio(item)
                        },
                        detailAction: { openDetails(item) },
                        shareAction: { Task { await share(item) } },
                        canRename: subscription.canImportAndSync,
                        renameAction: { renameItem = item },
                        canDelete: subscription.canImportAndSync,
                        deleteAction: { deleteItem(item) }
                    )
                } else {
                    DocumentListRow(
                        item: item,
                        openAction: {
                            stopAudioPlayback()
                            openDocument(item)
                        },
                        detailAction: { openDetails(item) },
                        shareAction: { Task { await share(item) } },
                        canRename: subscription.canImportAndSync,
                        renameAction: { renameItem = item },
                        canDelete: subscription.canImportAndSync,
                        deleteAction: { deleteItem(item) }
                    )
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(item: $renameItem) { item in
            RenameVaultItemSheet(item: item)
        }
        .onDisappear {
            stopAudioPlayback()
        }
    }

    @MainActor
    private func toggleAudioPlayback(_ item: VaultItem) async {
        if activeAudioId == item.id {
            stopAudioPlayback()
            return
        }

        stopAudioPlayback()
        loadingAudioId = item.id
        defer { loadingAudioId = nil }

        do {
            let url = try await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
            let audioPlayer = AVPlayer(url: url)
            let samplesTask = Task.detached(priority: .utility) {
                await AudioWaveformAnalyzer.samples(for: url)
            }
            MediaPreviewAudioSession.activateForPlayback()
            MediaPreviewAudioSession.configure(audioPlayer)
            player = audioPlayer
            activeAudioId = item.id
            activeAudioSamples = AudioWaveformAnalyzer.placeholderSamples
            audioCurrentTime = 0
            audioDuration = await AudioWaveformAnalyzer.duration(for: url)
            installAudioObservers(for: audioPlayer, itemId: item.id)
            audioPlayer.play()
            let samples = await samplesTask.value
            if activeAudioId == item.id {
                activeAudioSamples = samples
            }
        } catch {
            activeAudioId = nil
        }
    }

    @MainActor
    private func stopAudioPlayback() {
        if let audioTimeObserver, let player {
            player.removeTimeObserver(audioTimeObserver)
        }
        audioTimeObserver = nil
        player?.pause()
        player = nil
        activeAudioId = nil
        loadingAudioId = nil
        activeAudioSamples = AudioWaveformAnalyzer.placeholderSamples
        audioCurrentTime = 0
        audioDuration = 0
    }

    @MainActor
    private func seekActiveAudio(to progress: Double) {
        guard let player, audioDuration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let seconds = audioDuration * clamped
        audioCurrentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if activeAudioId != nil, player.timeControlStatus != .playing {
            MediaPreviewAudioSession.activateForPlayback()
            MediaPreviewAudioSession.configure(player)
            player.play()
        }
    }

    @MainActor
    private func installAudioObservers(for audioPlayer: AVPlayer, itemId: String) {
        if let audioTimeObserver, let player {
            player.removeTimeObserver(audioTimeObserver)
        }
        audioTimeObserver = audioPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard activeAudioId == itemId else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                audioCurrentTime = min(max(seconds, 0), max(audioDuration, 0))
            }
            if let itemDuration = audioPlayer.currentItem?.duration.seconds,
               itemDuration.isFinite,
               itemDuration > 0 {
                audioDuration = itemDuration
            }
            if audioDuration > 0, audioCurrentTime >= audioDuration - 0.05, audioPlayer.timeControlStatus != .playing {
                Task { @MainActor in
                    stopAudioPlayback()
                }
            }
        }
    }

    @MainActor
    private func share(_ item: VaultItem) async {
        let urls = await vaultStore.decryptedTemporaryURLs(for: [item], context: modelContext, sync: sync)
        guard !urls.isEmpty else { return }
        sharePayload = SharePayload(items: urls)
    }
}

private struct AudioListRow: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem
    let isPlaying: Bool
    let isLoading: Bool
    let waveformSamples: [CGFloat]
    let currentTime: Double
    let duration: Double
    let playAction: () -> Void
    let seekAction: (Double) -> Void
    let openAction: () -> Void
    let detailAction: () -> Void
    let shareAction: () -> Void
    let canRename: Bool
    let renameAction: () -> Void
    let canDelete: Bool
    let deleteAction: () -> Void

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: playAction) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? AppTheme.primaryFill : AppTheme.success.opacity(0.14))
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.72)
                            .tint(isPlaying ? .white : AppTheme.success)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isPlaying ? .white : AppTheme.success)
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(metadata?.originalName ?? L.string("Recording"))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                if isPlaying {
                    AudioWaveformScrubber(
                        samples: waveformSamples,
                        progress: duration > 0 ? currentTime / duration : 0,
                        tint: AppTheme.success,
                        onScrub: seekAction
                    )
                    .frame(height: 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                } else {
                    Text(audioDetailText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                if item.syncStatus == .failed || item.assetState == .failed {
                    HStack(spacing: 6) {
                        StatusPill(title: item.syncStatus.title, systemImage: "icloud", tint: AppTheme.warning)
                        StatusPill(title: item.assetState.title, systemImage: item.assetState.systemImage, tint: AppTheme.warning)
                    }
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button(action: openAction) {
                    Label(L.string("Open Player"), systemImage: "waveform")
                }
                Button(action: detailAction) {
                    Label(L.string("Details"), systemImage: "info.circle")
                }
                Button(action: shareAction) {
                    Label(L.string("Share"), systemImage: "square.and.arrow.up")
                }
                if canRename {
                    Button(action: renameAction) {
                        Label(L.string("Rename"), systemImage: "pencil")
                    }
                }
                if canDelete {
                    Button(role: .destructive, action: deleteAction) {
                        Label(L.string("Delete"), systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: openAction)
        .animation(.smooth(duration: 0.18), value: isPlaying)
        .animation(.smooth(duration: 0.12), value: currentTime)
        .accessibilityLabel(metadata?.originalName ?? L.string("Recording"))
    }

    private var audioDetailText: String {
        let size = ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)
        let date = (metadata?.importedAt ?? item.createdAt).formatted(date: .abbreviated, time: .shortened)
        let fileType = metadata?.originalExtension?.uppercased() ?? L.string("Audio")
        return "\(fileType) · \(size) · \(date)"
    }
}

private struct AudioWaveformScrubber: View {
    let samples: [CGFloat]
    let progress: Double
    let tint: Color
    let onScrub: (Double) -> Void
    @State private var dragProgress: Double?

    private var displayedProgress: Double {
        min(max(dragProgress ?? progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progressX = width * displayedProgress

            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(renderSamples.enumerated()), id: \.offset) { index, sample in
                        let barProgress = CGFloat(index) / CGFloat(max(renderSamples.count - 1, 1))
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(barProgress <= CGFloat(displayedProgress) ? tint : AppTheme.secondaryText.opacity(0.26))
                            .frame(width: 2.4, height: max(4, sample * proxy.size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: proxy.size.height + 4)
                    .offset(x: min(max(progressX - 1, 0), width - 2), y: -2)
                    .shadow(color: tint.opacity(0.38), radius: 4, x: 0, y: 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = min(max(value.location.x / width, 0), 1)
                        dragProgress = next
                        onScrub(next)
                    }
                    .onEnded { value in
                        let next = min(max(value.location.x / width, 0), 1)
                        dragProgress = nil
                        onScrub(next)
                    }
            )
        }
        .accessibilityLabel(L.string("Audio waveform"))
    }

    private var renderSamples: [CGFloat] {
        samples.isEmpty ? AudioWaveformAnalyzer.placeholderSamples : samples
    }
}

private enum AudioWaveformAnalyzer {
    nonisolated static let placeholderSamples: [CGFloat] = [
        0.28, 0.42, 0.24, 0.56, 0.36, 0.68, 0.32, 0.48,
        0.76, 0.34, 0.58, 0.44, 0.62, 0.26, 0.52, 0.38,
        0.72, 0.46, 0.30, 0.64, 0.40, 0.54, 0.78, 0.36,
        0.48, 0.66, 0.28, 0.58, 0.42, 0.74, 0.34, 0.50
    ]

    nonisolated static func duration(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 {
            return seconds
        }
        return 0
    }

    nonisolated static func samples(for url: URL, targetCount: Int = 56) async -> [CGFloat] {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard let track = tracks.first,
              let reader = try? AVAssetReader(asset: asset) else {
            return placeholderSamples
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            "AVLinearPCMIsNonInterleaved": false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return placeholderSamples }
        reader.add(output)
        guard reader.startReading() else { return placeholderSamples }

        var packetPeaks: [CGFloat] = []
        while let buffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(buffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    block,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &length,
                    dataPointerOut: &dataPointer
                )
                if status == kCMBlockBufferNoErr, let dataPointer, length > 0 {
                    let int16Pointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Int16.self)
                    let sampleCount = length / MemoryLayout<Int16>.size
                    var peak: Int16 = 0
                    for index in 0..<sampleCount {
                        let value = int16Pointer[index] == Int16.min ? Int16.max : abs(int16Pointer[index])
                        if value > peak {
                            peak = value
                        }
                    }
                    packetPeaks.append(CGFloat(peak) / CGFloat(Int16.max))
                }
            }
            CMSampleBufferInvalidate(buffer)
        }

        guard !packetPeaks.isEmpty else { return placeholderSamples }
        return resample(packetPeaks, targetCount: targetCount)
    }

    nonisolated private static func resample(_ values: [CGFloat], targetCount: Int) -> [CGFloat] {
        guard values.count > targetCount else {
            return values.map { max(0.08, min($0, 1)) }
        }
        return (0..<targetCount).map { index in
            let start = index * values.count / targetCount
            let end = max(start + 1, (index + 1) * values.count / targetCount)
            let peak = values[start..<min(end, values.count)].max() ?? 0
            return max(0.08, min(peak, 1))
        }
    }
}

private struct DocumentListRow: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem
    let openAction: () -> Void
    let detailAction: () -> Void
    let shareAction: () -> Void
    let canRename: Bool
    let renameAction: () -> Void
    let canDelete: Bool
    let deleteAction: () -> Void

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    private var descriptor: FileFormatDescriptor {
        FileFormatDescriptor(metadata: metadata, kind: item.kind)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(descriptor.tint.opacity(0.14))
                Image(systemName: descriptor.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(descriptor.tint)
            }
            .frame(width: 46, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(metadata?.originalName ?? L.string("Private File"))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(documentDetailText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                if item.syncStatus == .failed || item.assetState == .failed {
                    HStack(spacing: 6) {
                        StatusPill(title: item.syncStatus.title, systemImage: "icloud", tint: AppTheme.warning)
                        StatusPill(title: item.assetState.title, systemImage: item.assetState.systemImage, tint: AppTheme.warning)
                    }
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button(action: openAction) {
                    Label(L.string("Preview"), systemImage: "doc.viewfinder")
                }
                Button(action: detailAction) {
                    Label(L.string("Details"), systemImage: "info.circle")
                }
                Button(action: shareAction) {
                    Label(L.string("Share"), systemImage: "square.and.arrow.up")
                }
                if canRename {
                    Button(action: renameAction) {
                        Label(L.string("Rename"), systemImage: "pencil")
                    }
                }
                if canDelete {
                    Button(role: .destructive, action: deleteAction) {
                        Label(L.string("Delete"), systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: openAction)
        .accessibilityLabel(metadata?.originalName ?? L.string("Private File"))
    }

    private var documentDetailText: String {
        let size = ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)
        let date = (metadata?.importedAt ?? item.createdAt).formatted(date: .abbreviated, time: .shortened)
        return "\(descriptor.label) · \(size) · \(date)"
    }
}

private struct RenameVaultItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    let item: VaultItem
    @State private var name = ""
    @State private var isSaving = false

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.string("File Name"), text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await save() }
                        }
                } footer: {
                    Text(L.string("If no extension is entered, the original extension is kept."))
                }
            }
            .navigationTitle(L.string("Rename"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.string("Cancel")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? L.string("Saving") : L.string("Save")) {
                        Task { await save() }
                    }
                    .disabled(!canSave || !subscription.canImportAndSync)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if name.isEmpty {
                name = metadata?.originalName ?? fallbackName
            }
        }
    }

    @MainActor
    private func save() async {
        guard canSave, subscription.canImportAndSync else { return }
        isSaving = true
        await vaultStore.rename(item, to: name, context: modelContext, sync: sync)
        isSaving = false
        dismiss()
    }

    private var fallbackName: String {
        item.kind == .audio ? L.string("Recording") : L.string("Private File")
    }
}

private struct FileFormatDescriptor {
    let icon: String
    let label: String
    let tint: Color

    init(metadata: VaultMetadata?, kind: VaultItemKind) {
        let ext = metadata?.originalExtension?.lowercased() ?? ""
        let mime = metadata?.mimeType.lowercased() ?? ""
        let type = UTType(filenameExtension: ext)

        if ext == "pdf" || mime.contains("pdf") {
            icon = "doc.richtext.fill"
            label = "PDF"
            tint = AppTheme.warning
        } else if ["doc", "docx"].contains(ext) || mime.contains("wordprocessingml") || mime.contains("msword") || mime.contains("word") {
            icon = "doc.text.fill"
            label = "Word"
            tint = AppTheme.primary
        } else if ext == "pages" {
            icon = "doc.text.fill"
            label = "Pages"
            tint = AppTheme.primary
        } else if ext == "rtf" || mime.contains("rtf") {
            icon = "doc.text.fill"
            label = "RTF"
            tint = AppTheme.primary
        } else if ["xls", "xlsx"].contains(ext) || mime.contains("spreadsheetml") || mime.contains("excel") {
            icon = "tablecells.fill"
            label = "Excel"
            tint = AppTheme.success
        } else if ext == "numbers" {
            icon = "tablecells.fill"
            label = "Numbers"
            tint = AppTheme.success
        } else if ext == "csv" || mime.contains("csv") {
            icon = "tablecells.fill"
            label = "CSV"
            tint = AppTheme.success
        } else if ["ppt", "pptx"].contains(ext) || mime.contains("presentationml") || mime.contains("powerpoint") {
            icon = "rectangle.on.rectangle.angled"
            label = "PowerPoint"
            tint = AppTheme.accent
        } else if ext == "key" {
            icon = "rectangle.on.rectangle.angled"
            label = "Keynote"
            tint = AppTheme.accent
        } else if type?.conforms(to: .image) == true || ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "raw", "dng", "svg"].contains(ext) {
            icon = "photo.fill"
            label = ext.isEmpty ? L.string("Image") : ext.uppercased()
            tint = AppTheme.primary
        } else if type?.conforms(to: .movie) == true || ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) {
            icon = "video.fill"
            label = ext.isEmpty ? L.string("Video") : ext.uppercased()
            tint = AppTheme.accent
        } else if type?.conforms(to: .audio) == true || ["m4a", "mp3", "wav", "aac", "aiff", "flac", "caf", "ogg"].contains(ext) {
            icon = "waveform"
            label = ext.isEmpty ? L.string("Audio") : ext.uppercased()
            tint = AppTheme.success
        } else if ["md", "markdown"].contains(ext) {
            icon = "text.alignleft"
            label = "Markdown"
            tint = AppTheme.primary
        } else if ["txt", "json", "xml", "yaml", "yml", "log"].contains(ext) || mime.hasPrefix("text/") {
            icon = "doc.plaintext.fill"
            label = ext.isEmpty ? L.string("Text") : ext.uppercased()
            tint = AppTheme.secondaryText
        } else if ["swift", "js", "ts", "tsx", "jsx", "html", "css", "py", "java", "kt", "c", "cpp", "h", "m", "mm", "php", "rb", "go", "rs", "sh", "sql"].contains(ext) {
            icon = "curlybraces"
            label = ext.uppercased()
            tint = AppTheme.ink
        } else if kind == .archive || ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "jar", "ipa", "apk"].contains(ext) || mime.contains("zip") || mime.contains("archive") || mime.contains("compressed") {
            icon = "archivebox.fill"
            label = ext.isEmpty ? L.string("Archive") : ext.uppercased()
            tint = AppTheme.ink
        } else if ["psd", "ai", "indd", "xd", "fig", "sketch"].contains(ext) {
            icon = "paintpalette.fill"
            label = ext.uppercased()
            tint = AppTheme.accent
        } else if ["epub", "mobi", "azw", "azw3"].contains(ext) {
            icon = "book.closed.fill"
            label = ext.uppercased()
            tint = AppTheme.primary
        } else if ["ics", "vcf"].contains(ext) {
            icon = ext == "ics" ? "calendar" : "person.crop.square"
            label = ext.uppercased()
            tint = AppTheme.success
        } else {
            icon = kind.previewBadgeSystemImage ?? "doc.fill"
            label = ext.isEmpty ? kind.detailTitle : ext.uppercased()
            tint = AppTheme.secondaryText
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

struct VaultMediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    let items: [VaultItem]
    let initialItemId: String
    @State private var selectedId: String
    @State private var previewItems: [VaultItem]
    @State private var sharePayload: SharePayload?
    @State private var detailItem: VaultItem?
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

                    Menu {
                        Button {
                            detailItem = selectedItem
                        } label: {
                            Label(L.string("Details"), systemImage: "info.circle")
                        }

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

                        if subscription.canImportAndSync {
                            Button(role: .destructive) {
                                Task { await deleteSelectedItem() }
                            } label: {
                                Label(L.string("Delete"), systemImage: "trash")
                            }
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
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(item: $detailItem) { item in
            MediaPreviewDetailSheet(item: item)
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
        guard subscription.canImportAndSync else { return }
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

private struct MediaPreviewDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    @State private var technicalRows: [MediaDetailRow] = []
    @State private var isLoadingTechnicalDetails = true

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L.string("File")) {
                    detailRow(L.string("Name"), metadata?.originalName ?? L.string("Private Item"))
                    detailRow(L.string("Type"), item.kind.detailTitle)
                    detailRow(L.string("Size"), ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                    detailRow(L.string("MIME Type"), metadata?.mimeType)
                    detailRow(L.string("Extension"), metadata?.originalExtension?.isEmpty == false ? metadata?.originalExtension : nil)
                    detailRow(L.string("Source"), metadata?.source)
                }

                Section(L.string("Dates")) {
                    detailRow(L.string("Imported"), metadata?.importedAt.formatted(date: .abbreviated, time: .shortened))
                    detailRow(L.string("Created in App"), item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    detailRow(L.string("Updated"), item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let downloadedAt = item.downloadedAt {
                        detailRow(L.string("Downloaded"), downloadedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section(L.string("Media")) {
                    if isLoadingTechnicalDetails {
                        ProgressView()
                    } else if technicalRows.isEmpty {
                        detailRow(L.string("Metadata"), nil)
                    } else {
                        ForEach(technicalRows) { row in
                            detailRow(row.title, row.value)
                        }
                    }
                }

                Section(L.string("iCloud")) {
                    detailRow(L.string("Upload Status"), item.syncStatus.title)
                    detailRow(L.string("Storage State"), item.assetState.title)
                    detailRow(L.string("Cloud Record"), item.cloudRecordName)
                    if item.syncStatus == .failed {
                        detailRow(L.string("Failure Reason"), item.lastSyncError ?? sync.lastSyncError)
                    }
                    if item.assetState == .failed {
                        detailRow(L.string("Download Failure"), item.lastDownloadError)
                    }
                    Text(L.string("Encrypted iCloud Sync is always on. Items are encrypted on this device before upload to your private iCloud."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle(L.string("Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.string("Done")) {
                        dismiss()
                    }
                }
            }
        }
        .task(id: item.id) {
            await loadTechnicalDetails()
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 16)
            Text(value?.isEmpty == false ? value! : L.string("Not Available"))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
        }
    }

    @MainActor
    private func loadTechnicalDetails() async {
        isLoadingTechnicalDetails = true
        defer { isLoadingTechnicalDetails = false }
        guard item.kind == .image || item.kind == .video else {
            technicalRows = []
            return
        }
        do {
            let url = try await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
            if item.kind == .image {
                technicalRows = imageRows(url: url)
            } else {
                technicalRows = await videoRows(url: url)
            }
        } catch {
            technicalRows = [MediaDetailRow(title: L.string("Read Error"), value: error.localizedDescription)]
        }
    }

    private func imageRows(url: URL) -> [MediaDetailRow] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return []
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let date = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        let lens = exif?[kCGImagePropertyExifLensModel] as? String

        return [
            MediaDetailRow(title: L.string("Dimensions"), value: pixelSizeText(width: width, height: height)),
            MediaDetailRow(title: L.string("Photo Time"), value: date),
            MediaDetailRow(title: L.string("Camera"), value: [make, model].compactMap { $0 }.joined(separator: " ")),
            MediaDetailRow(title: L.string("Lens"), value: lens)
        ].filter { $0.value?.isEmpty == false }
    }

    private func videoRows(url: URL) async -> [MediaDetailRow] {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map { formatDuration($0.seconds) }
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let firstTrack = tracks.first
        let naturalSize = try? await firstTrack?.load(.naturalSize)
        let transform = try? await firstTrack?.load(.preferredTransform)
        let size = transformedSize(naturalSize, transform: transform)
        let metadataItems = (try? await asset.load(.metadata)) ?? []
        let creationDateItem = metadataItems.first { item in
            let commonKey = item.commonKey?.rawValue ?? ""
            let metadataKey = item.key.map { String(describing: $0) } ?? ""
            return commonKey == "creationDate" || metadataKey.localizedCaseInsensitiveContains("creation")
        }
        let creationDate = try? await creationDateItem?.load(.stringValue)

        return [
            MediaDetailRow(title: L.string("Dimensions"), value: pixelSizeText(width: size?.width, height: size?.height)),
            MediaDetailRow(title: L.string("Duration"), value: duration),
            MediaDetailRow(title: L.string("Media Time"), value: creationDate)
        ].filter { $0.value?.isEmpty == false }
    }

    private func transformedSize(_ size: CGSize?, transform: CGAffineTransform?) -> (width: Int, height: Int)? {
        guard let size else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform ?? .identity)
        return (Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
    }

    private func pixelSizeText(width: Int?, height: Int?) -> String {
        guard let width, let height, width > 0, height > 0 else { return "" }
        return "\(width) x \(height)"
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private struct MediaDetailRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String?
}

private struct AudioDetailPlayerView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "AudioDetail")
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var detailItem: VaultItem?

    private var title: String {
        vaultStore.metadata(for: item)?.originalName ?? L.string("Recording")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    AudioPreviewPanel(title: title, player: player)
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(errorMessage ?? L.string("Unable to load this recording."))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        detailItem = item
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .sheet(item: $detailItem) { item in
            MediaPreviewDetailSheet(item: item)
        }
        .task(id: item.id) {
            await load()
        }
        .onDisappear {
            player?.pause()
            MediaPreviewAudioSession.deactivate()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        player?.pause()
        player = nil
        defer { isLoading = false }

        do {
            let url = try await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
            let audioPlayer = AVPlayer(url: url)
            MediaPreviewAudioSession.activateForPlayback()
            MediaPreviewAudioSession.configure(audioPlayer)
            player = audioPlayer
        } catch {
            Self.logger.error("Audio detail load failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentDetailPreviewView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "DocumentDetail")
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    @State private var previewURL: URL?
    @State private var markdownText: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var detailItem: VaultItem?
    @State private var sharePayload: SharePayload?

    private var title: String {
        vaultStore.metadata(for: item)?.originalName ?? L.string("Private File")
    }

    var body: some View {
        NavigationStack {
            Group {
                if let markdownText {
                    MarkdownDocumentPreview(text: markdownText)
                } else if let previewURL {
                    DocumentPreviewContainer(url: previewURL)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        L.string("Preview unavailable"),
                        systemImage: item.kind.previewBadgeSystemImage ?? "doc",
                        description: Text(errorMessage ?? L.string("Export this item to open it in another app."))
                    )
                }
            }
            .background(AppTheme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.string("Done")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            detailItem = item
                        } label: {
                            Label(L.string("Details"), systemImage: "info.circle")
                        }
                        Button {
                            Task { await exportItem() }
                        } label: {
                            Label(L.string("Export"), systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $detailItem) { item in
            MediaPreviewDetailSheet(item: item)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .task(id: item.id) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        previewURL = nil
        markdownText = nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            let url = try await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
            if isMarkdownDocument {
                markdownText = try String(contentsOf: url, encoding: .utf8)
            } else {
                previewURL = url
            }
        } catch {
            Self.logger.error("Document preview load failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private var isMarkdownDocument: Bool {
        guard let ext = vaultStore.metadata(for: item)?.originalExtension?.lowercased() else { return false }
        return ext == "md" || ext == "markdown"
    }

    @MainActor
    private func exportItem() async {
        let urls = await vaultStore.decryptedTemporaryURLs(for: [item], context: modelContext, sync: sync)
        guard !urls.isEmpty else { return }
        sharePayload = SharePayload(items: urls)
    }
}

private struct MarkdownDocumentPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Markdown(text)
                .markdownTheme(.gitHub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(AppTheme.background)
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

private struct VaultPeekPreviewOverlay: View {
    let item: VaultItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea()

            FullscreenMediaPage(item: item, isSelected: true)
                .ignoresSafeArea()
        }
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
    var detailTitle: String {
        switch self {
        case .image: L.string("Image")
        case .livePhoto: L.string("Live Photo")
        case .video: L.string("Video")
        case .audio: L.string("Audio")
        case .document: L.string("Document")
        case .archive: L.string("Archive")
        case .link: L.string("Link")
        case .other: L.string("Other")
        }
    }

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
    var usesListLayout: Bool {
        self == .audio || self == .documents
    }

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

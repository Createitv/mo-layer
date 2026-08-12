import AVFoundation
import ImageIO
import MapKit
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

private enum VaultHaptics {
    @MainActor
    static func moLayerTransferSucceeded() {
        PlatformCapabilities.successNotification()
    }
}

enum MediaPreviewRepairBatchPolicy {
    nonisolated static let maxAutomaticRepairCount = 48

    nonisolated static func candidateIDs(
        orderedItemIDs: [String],
        visibleItemIDs: Set<String>,
        repairNeededItemIDs: Set<String>,
        limit: Int = maxAutomaticRepairCount
    ) -> [String] {
        guard limit > 0 else { return [] }
        return Array(
            orderedItemIDs.lazy.filter {
                visibleItemIDs.contains($0) && repairNeededItemIDs.contains($0)
            }.prefix(limit)
        )
    }

    nonisolated static func taskKey(scope: String, visibleItemIDs: Set<String>) -> String {
        "\(scope):\(visibleItemIDs.sorted().joined(separator: ","))"
    }
}

private let vaultHomePerformanceLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy",
    category: "VaultHomePerformance"
)

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
            await vaultStore.bootstrap(
                context: modelContext,
                sync: sync,
                allowsCloudSync: subscription.canPullFromCloud,
                allowsCloudWrite: false
            )
            refreshPendingSharedImports()
            runBackgroundCloudSync()
        }
        .onChange(of: scenePhase) { _, phase in
            if auth.shouldLock(for: phase) {
                auth.lock()
            } else if phase == .active {
                vaultStore.setWriteAccess(subscription.canImportAndSync)
                _ = vaultStore.offloadOriginalsIfNeeded(context: modelContext)
                refreshPendingSharedImports()
                Task {
                    await vaultStore.syncCloudToLocal(
                        context: modelContext,
                        sync: sync,
                        allowsCloudSync: subscription.canPullFromCloud,
                        allowsCloudWrite: subscription.canImportAndSync
                    )
                }
            }
        }
        .onChange(of: subscription.canImportAndSync) { _, canWrite in
            vaultStore.setWriteAccess(canWrite)
        }
        .onChange(of: subscription.canPullFromCloud) { _, canPull in
            guard canPull else { return }
            Task {
                await vaultStore.syncCloudToLocal(
                    context: modelContext,
                    sync: sync,
                    allowsCloudSync: canPull,
                    allowsCloudWrite: subscription.canImportAndSync
                )
            }
        }
        .onOpenURL { url in
            Task {
                if url.scheme != "privacy", !url.isFileURL {
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
                destination: pendingSharedImports.first?.destination ?? .regular,
                canImportAndSync: canImportVaultItems(count: pendingSharedImports.count),
                isImporting: isImportingSharedFiles,
                message: sharedImportMessage,
                saveAction: { selectedImports in
                    Task { await savePendingSharedImports(selectedImports) }
                },
                cancelAction: discardPendingSharedImports
            )
        }
        .background(AppGlassBackground().ignoresSafeArea())
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
    private func savePendingSharedImports(_ selectedImports: [ImportService.PendingSharedImport]) async {
        guard !isImportingSharedFiles else { return }
        guard canImportVaultItems(count: selectedImports.count) else {
            sharedImportMessage = freeImportLimitMessage()
            return
        }
        guard !selectedImports.isEmpty else { return }

        isImportingSharedFiles = true
        sharedImportMessage = L.string("Encrypting and saving shared files...")
        defer { isImportingSharedFiles = false }
        vaultStore.setWriteAccess(true)

        let selectedIds = Set(selectedImports.map(\.id))
        let skippedImports = pendingSharedImports.filter { !selectedIds.contains($0.id) }
        ImportService.discardSharedImports(skippedImports)

        let result = await ImportService.importPendingSharedImports(
            selectedImports,
            context: modelContext,
            vaultStore: vaultStore,
            sync: sync,
            folderId: selectedImports.first?.destination.folderId,
            syncAfterImport: false
        )
        pendingSharedImports = ImportService.pendingSharedImports()
        if result.failedCount == 0 {
            pendingSharedImports = []
            if result.importedCount > 0 {
                sharedImportMessage = nil
                routeToImportedCategory(result)
                runBackgroundPendingSyncIfAllowed()
            } else {
                sharedImportMessage = result.displayMessage
            }
        } else {
            sharedImportMessage = L.string("Some files could not be saved. You can retry or cancel.")
        }
    }

    @MainActor
    private func autoSavePendingSharedImports() async {
        guard !isImportingSharedFiles else { return }
        let pending = ImportService.pendingSharedImports()
        guard canImportVaultItems(count: pending.count) else {
            refreshPendingSharedImports()
            sharedImportMessage = freeImportLimitMessage()
            return
        }

        guard !pending.isEmpty else {
            pendingSharedImports = []
            sharedImportMessage = nil
            return
        }

        isImportingSharedFiles = true
        sharedImportMessage = L.string("Encrypting and saving shared files...")
        vaultStore.setWriteAccess(true)
        let result = await ImportService.importPendingSharedImports(
            pending,
            context: modelContext,
            vaultStore: vaultStore,
            sync: sync,
            folderId: nil,
            syncAfterImport: false
        )
        pendingSharedImports = ImportService.pendingSharedImports()
        if result.failedCount == 0 {
            pendingSharedImports = []
            if result.importedCount > 0 {
                sharedImportMessage = nil
                routeToImportedCategory(result)
                runBackgroundPendingSyncIfAllowed()
            } else {
                sharedImportMessage = result.displayMessage
            }
        } else {
            sharedImportMessage = L.string("Some files could not be saved. You can retry or cancel.")
        }
        isImportingSharedFiles = false
    }

    @MainActor
    private func presentPendingSharedImportsFromExtension() async {
        refreshPendingSharedImports()
        guard !pendingSharedImports.isEmpty else { return }
        if canImportVaultItems(count: pendingSharedImports.count) {
            sharedImportMessage = L.string("Review these shared files. Photos, videos, audio, and files will be saved into their matching vault sections.")
        } else {
            sharedImportMessage = freeImportLimitMessage()
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

    private func runBackgroundCloudSync() {
        Task { @MainActor in
            await vaultStore.syncCloudToLocal(
                context: modelContext,
                sync: sync,
                allowsCloudSync: subscription.canPullFromCloud,
                allowsCloudWrite: subscription.canImportAndSync
            )
        }
    }

    private func runBackgroundPendingSyncIfAllowed() {
        guard subscription.canImportAndSync else { return }
        Task { @MainActor in
            await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
        }
    }

    @MainActor
    private func canImportVaultItems(count incomingCount: Int) -> Bool {
        let items = (try? modelContext.fetch(FetchDescriptor<VaultItem>())) ?? []
        return VaultFreeImportPolicy.canImport(
            currentCount: VaultFreeImportPolicy.countedItemCount(in: items),
            incomingCount: incomingCount,
            isPro: subscription.isPro
        )
    }

    private func freeImportLimitMessage() -> String {
        L.format("Free vaults can hold up to %d photos, videos, audio, and files. Open Pro to keep adding.", VaultFreeImportPolicy.freeItemLimit)
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

enum VaultSelectionPolicy {
    nonisolated static func canSelect(_ item: VaultItem) -> Bool {
        item.deletedAt == nil && item.kind.isCategorySelectionItem
    }

    nonisolated static func selectableItems(in items: [VaultItem], category: VaultCategory) -> [VaultItem] {
        category.items(from: items).filter(canSelect)
    }
}

struct SharedImportReviewSheet: View {
    let imports: [ImportService.PendingSharedImport]
    let destination: SharedImportDestination
    let canImportAndSync: Bool
    let isImporting: Bool
    let message: String?
    let saveAction: ([ImportService.PendingSharedImport]) -> Void
    let proAction: (() -> Void)?
    let cancelAction: () -> Void
    @State private var selectedImportIds: Set<String>

    init(
        imports: [ImportService.PendingSharedImport],
        destination: SharedImportDestination = .regular,
        canImportAndSync: Bool = true,
        isImporting: Bool,
        message: String?,
        saveAction: @escaping ([ImportService.PendingSharedImport]) -> Void,
        proAction: (() -> Void)? = nil,
        cancelAction: @escaping () -> Void
    ) {
        self.imports = imports
        self.destination = destination
        self.canImportAndSync = canImportAndSync
        self.isImporting = isImporting
        self.message = message
        self.saveAction = saveAction
        self.proAction = proAction
        self.cancelAction = cancelAction
        _selectedImportIds = State(initialValue: Set(imports.map(\.id)))
    }

    private var selectedImports: [ImportService.PendingSharedImport] {
        imports.filter { selectedImportIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: destination.icon)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(destination.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(destination.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text(L.string("Save Location"))
                    }

                    Section {
                        ForEach(imports) { item in
                            Button {
                                toggleSelection(for: item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedImportIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedImportIds.contains(item.id) ? AppTheme.primary : AppTheme.secondaryText)
                                        .frame(width: 28, height: 28)

                                    SharedImportThumbnailView(item: item)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.originalName)
                                            .font(.headline)
                                            .lineLimit(2)
                                            .foregroundStyle(AppTheme.ink)
                                        Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(isImporting)
                        }
                    } header: {
                        Text(L.string("Shared Files"))
                    } footer: {
                        Text(L.string("Unselected shared files will be deleted. Selected files are saved locally first. Pro keeps encrypted iCloud backup running in the background."))
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

                if !canImportAndSync {
                    Label(L.format("Free vaults can hold up to %d photos, videos, audio, and files. Open Pro to keep adding.", VaultFreeImportPolicy.freeItemLimit), systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                VStack(spacing: 10) {
                    if canImportAndSync {
                        Button {
                            saveAction(selectedImports)
                        } label: {
                            Label(isImporting ? L.string("Saving") : L.string("Confirm Save"), systemImage: "lock.doc")
                        }
                        .buttonStyle(AppButtonStyle())
                        .disabled(isImporting || selectedImports.isEmpty)
                    } else if let proAction {
                        Button(action: proAction) {
                            Label(L.string("Open Pro and keep adding"), systemImage: "lock.open.fill")
                        }
                        .buttonStyle(AppButtonStyle())
                        .disabled(isImporting)
                    }

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
            .onChange(of: imports.map(\.id)) { _, ids in
                let availableIds = Set(ids)
                let retainedIds = selectedImportIds.intersection(availableIds)
                selectedImportIds = retainedIds.isEmpty ? availableIds : retainedIds
            }
        }
    }

    private func toggleSelection(for item: ImportService.PendingSharedImport) {
        if selectedImportIds.contains(item.id) {
            selectedImportIds.remove(item.id)
        } else {
            selectedImportIds.insert(item.id)
        }
    }

}

private struct SharedImportThumbnailView: View {
    let item: ImportService.PendingSharedImport
    @State private var thumbnail: UIImage?
    @State private var didLoad = false

    private var kind: SharedImportPreviewKind {
        SharedImportPreviewKind(item: item)
    }

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.primary.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.black.opacity(0.58))
                    .clipShape(Circle())
                    .padding(4)
            }
        }
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.primary.opacity(0.1))
            if !didLoad, kind.supportsThumbnail {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(AppTheme.primary)
            } else {
                Image(systemName: kind.fallbackIcon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary)
            }
        }
    }

    @MainActor
    private func loadThumbnail() async {
        thumbnail = nil
        didLoad = false
        guard kind.supportsThumbnail else {
            didLoad = true
            return
        }

        let fileURL = item.fileURL
        let typeIdentifier = item.typeIdentifier
        let mimeType = item.mimeType
        let data = await Task.detached(priority: .utility) {
            await SharedImportThumbnailRenderer.makeThumbnailData(
                for: fileURL,
                typeIdentifier: typeIdentifier,
                mimeType: mimeType
            )
        }.value
        thumbnail = data.flatMap(UIImage.init(data:))
        didLoad = true
    }
}

private enum SharedImportPreviewKind: Equatable {
    case image
    case video
    case audio
    case archive
    case document

    init(item: ImportService.PendingSharedImport) {
        self.init(type: item.sharedImportContentType, fileExtension: item.fileURL.pathExtension)
    }

    nonisolated init(type: UTType?, fileExtension: String) {
        let ext = fileExtension.lowercased()
        if type?.conforms(to: .image) == true || Self.imageExtensions.contains(ext) {
            self = .image
        } else if type?.conforms(to: .movie) == true || Self.videoExtensions.contains(ext) {
            self = .video
        } else if type?.conforms(to: .audio) == true {
            self = .audio
        } else if type?.conforms(to: .archive) == true {
            self = .archive
        } else {
            self = .document
        }
    }

    var supportsThumbnail: Bool {
        self == .image || self == .video
    }

    var fallbackIcon: String {
        switch self {
        case .image:
            "photo"
        case .video:
            "video"
        case .audio:
            "waveform"
        case .archive:
            "archivebox"
        case .document:
            "doc"
        }
    }

    nonisolated private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif"
    ]

    nonisolated private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "hevc"
    ]
}

private enum SharedImportThumbnailRenderer {
    nonisolated static func makeThumbnailData(
        for fileURL: URL,
        typeIdentifier: String,
        mimeType: String
    ) async -> Data? {
        let type = UTType(typeIdentifier)
            ?? UTType(mimeType: mimeType)
            ?? UTType(filenameExtension: fileURL.pathExtension)
        let kind = SharedImportPreviewKind(type: type, fileExtension: fileURL.pathExtension)

        switch kind {
        case .image:
            return makeImageThumbnailData(from: fileURL)
        case .video:
            return await makeVideoThumbnailData(from: fileURL)
        case .audio, .archive, .document:
            return nil
        }
    }

    nonisolated private static func makeImageThumbnailData(from fileURL: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return makeJPEGData(from: image)
    }

    nonisolated private static func makeVideoThumbnailData(from fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let times = [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime(seconds: 1, preferredTimescale: 600)
        ]
        for time in times {
            if let image = try? await generateImage(with: generator, at: time) {
                return makeJPEGData(from: image)
            }
        }
        return nil
    }

    nonisolated private static func generateImage(
        with generator: AVAssetImageGenerator,
        at time: CMTime
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    nonisolated private static func makeJPEGData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

private extension ImportService.PendingSharedImport {
    var sharedImportContentType: UTType? {
        UTType(typeIdentifier)
            ?? UTType(mimeType: mimeType)
            ?? UTType(filenameExtension: fileURL.pathExtension)
    }
}

struct VaultHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var desktopDetailItem: VaultItem?
    @State private var sharePayload: SharePayload?
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var showProfileCenter = false
    @State private var showImportHub = false
    @State private var showQuickRecorder = false
    @State private var showMembership = false
    @State private var showMoLayerProPrompt = false
    @State private var selectedCategory: VaultCategory = .album
    @State private var albumMediaFilter: AlbumMediaFilter = .all
    @State private var isAlbumFilterPickerPresented = false
    @State private var importSummary: ImportSummary?
    @State private var selectionMode = false
    @State private var selectedItemIds: Set<String> = []
    @State private var confirmBulkDelete = false
    @State private var isDeletingSelection = false
    @State private var isExportingSelection = false
    @State private var isSavingSelectionToPhotos = false
    @State private var photoSaveAlert: PhotoSaveAlert?
    @State private var photoSaveToast: AppToast?
    @State private var photoSaveToastDismissTask: Task<Void, Never>?
    @State private var isInnerVaultActive = false
    @State private var sweepSelectionAnchorId: String?
    @State private var mediaGridItemFrames: [AnyHashable: CGRect] = [:]
    @State private var albumGridContentHeight: CGFloat = 1
    @State private var isRepairingMediaPreviews = false
    @State private var visibleAlbumItemIDs = Set<String>()
    @State private var peekItem: VaultItem?
    @State private var peekTouchItemId: String?
    @State private var peekTask: Task<Void, Never>?
    @State private var suppressTapUntil: Date?
    @State private var moLayerTouchZoneFrame: CGRect = .zero
    @State private var showMoLayerGuide = false
    @AppStorage("vault.hasSeenMoLayerGuide") private var hasSeenMoLayerGuide = false
    @AppStorage(MediaGridScaleStorage.albumKey) private var albumGridScale = MediaGridScaleStorage.defaultStoredScale
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
        guard selectedCategory == .album else { return categoryItems }
        return albumMediaFilter.items(from: categoryItems)
    }
    private var mediaPreviewRepairCandidates: [VaultItem] {
        guard selectedCategory == .album else { return [] }
        let visibleItemsOnScreen = visibleItems.filter { visibleAlbumItemIDs.contains($0.id) }
        let repairNeededIDs = Set(
            visibleItemsOnScreen.lazy
                .filter { vaultStore.needsMediaPreviewRepair($0) }
                .map(\.id)
        )
        let candidateIDs = MediaPreviewRepairBatchPolicy.candidateIDs(
            orderedItemIDs: visibleItemsOnScreen.map(\.id),
            visibleItemIDs: visibleAlbumItemIDs,
            repairNeededItemIDs: repairNeededIDs
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: visibleItemsOnScreen.map { ($0.id, $0) })
        return candidateIDs.compactMap { itemsByID[$0] }
    }
    private var mediaPreviewRepairKey: String {
        MediaPreviewRepairBatchPolicy.taskKey(
            scope: "\(isInnerVaultActive ? "inner" : "default"):\(selectedCategory.rawValue):\(albumMediaFilter.rawValue)",
            visibleItemIDs: visibleAlbumItemIDs
        )
    }
    private var selectableVisibleItems: [VaultItem] {
        VaultSelectionPolicy.selectableItems(in: visibleItems, category: selectedCategory)
    }
    private var selectedVisibleItems: [VaultItem] {
        visibleItems.filter { selectedItemIds.contains($0.id) }
    }
    private var selectedItemsCanSaveToPhotos: Bool {
        selectedVisibleItems.contains { PhotoLibraryExportService.canSaveToPhotoLibrary(kind: $0.kind) }
    }
    private var selectionWorkStatusText: String? {
        if isSavingSelectionToPhotos {
            return L.string("Saving to Photos")
        }
        if isExportingSelection {
            return L.string("Preparing")
        }
        return nil
    }
    private var freeImportItemCount: Int {
        VaultFreeImportPolicy.countedItemCount(in: activeItems)
    }
    private var shouldShowFreeImportLimitBanner: Bool {
        !subscription.isPro && freeImportItemCount >= VaultFreeImportPolicy.freeItemLimit
    }
    private func canImportVaultItems(count incomingCount: Int) -> Bool {
        VaultFreeImportPolicy.canImport(
            currentCount: freeImportItemCount,
            incomingCount: incomingCount,
            isPro: subscription.isPro
        )
    }
    private var importDestinationFolderId: String? {
        isInnerVaultActive ? VaultStore.innerVaultFolderId : nil
    }
    private var usesSplitLayout: Bool {
        PlatformCapabilities.usesDesktopLayout || horizontalSizeClass == .regular
    }
    private var folderContextStyle: VaultFolderContextStyle {
        VaultFolderContextStyle(isInnerVaultActive: isInnerVaultActive)
    }
    private var categoryCounts: [VaultCategory: Int] {
        Dictionary(uniqueKeysWithValues: VaultCategory.homeModes.map { category in
            (category, category.items(from: spaceItems).count)
        })
    }
    private var detailSheetBinding: Binding<VaultItem?> {
        Binding {
            usesSplitLayout ? nil : selectedItem
        } set: { value in
            selectedItem = value
        }
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                splitHomeContent
            } else {
                compactHomeContent
            }
        }
        .sheet(item: detailSheetBinding) { item in
            VaultItemDetailView(item: item)
        }
        .fullScreenCover(item: $audioDetailItem) { item in
            AudioDetailPlayerView(item: item)
        }
        .fullScreenCover(item: $documentDetailItem) { item in
            DocumentDetailPreviewView(item: item, isInnerVaultActive: isInnerVaultActive)
        }
        .fullScreenCover(item: $previewSelection) { selection in
            VaultMediaPreviewView(
                items: selection.items,
                initialItemId: selection.initialItemId,
                isInnerVaultActive: isInnerVaultActive
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
        .fullScreenCover(isPresented: $showQuickRecorder) {
            AudioRecorderView { url, completion in
                guard canImportVaultItems(count: 1) else {
                    showMembership = true
                    completion(false)
                    return
                }
                Task {
                    vaultStore.setWriteAccess(true)
                    let summary = await ImportService.importFiles(
                        urls: [url],
                        context: modelContext,
                        vaultStore: vaultStore,
                        sync: sync,
                        source: "Quick Recorder",
                        syncAfterImport: subscription.canImportAndSync
                    )
                    try? FileManager.default.removeItem(at: url)
                    if subscription.canImportAndSync {
                        await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
                    }
                    handleImportCompletion(summary)
                    completion(summary.importedCount > 0)
                }
            }
        }
        .fullScreenCover(isPresented: $showProfileCenter) {
            ProfileCenterView(showMoLayerTutorialAction: {
                showProfileCenter = false
                showMoLayerGuide = true
            })
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
            presentMoLayerGuideIfNeeded()
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
        .alert(item: $importSummary) { summary in
            Alert(
                title: Text(summary.displayTitle),
                message: Text(summary.displayMessage),
                dismissButton: .default(Text(L.string("OK")))
            )
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
        .alert(L.string("Mo Layer"), isPresented: $showMoLayerProPrompt) {
            Button(L.string("Cancel"), role: .cancel) {}
            Button(L.string("Open Pro")) {
                showMembership = true
            }
        } message: {
            Text(L.string("Mo Layer is a Pro feature. It is a deeper hidden directory inside the real vault for files that need extra privacy. With Pro, you can hide files in Mo Layer and restore them to the regular vault at any time."))
        }
        .alert(L.string("Delete Selected Items?"), isPresented: $confirmBulkDelete) {
            Button(L.string("Cancel"), role: .cancel) {}
            Button(L.string("Delete"), role: .destructive) {
                Task { await deleteSelectedItems() }
            }
        } message: {
            Text(L.format("%d selected item(s) will be removed from this device and marked for removal from iCloud.", selectedItemIds.count))
        }
        .overlay {
            if showMoLayerGuide {
                MoLayerTutorialOverlay(
                    touchZoneFrame: moLayerTouchZoneFrame,
                    enterMoLayerAction: enterInnerVault,
                    completeAction: completeMoLayerGuide,
                    dismissAction: { showMoLayerGuide = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay(alignment: .top) {
            if let photoSaveToast {
                AppToastView(toast: photoSaveToast)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var compactHomeContent: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                scrollContent
            }
            .background(AppGlassBackground().ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                bottomInsetContent
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                albumFilterButton
                    .padding(.trailing, 18)
                    .padding(.bottom, 38)
            }
            .overlay {
                if let peekItem {
                    VaultPeekPreviewOverlay(item: peekItem)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var splitHomeContent: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            VaultSidebarView(
                selectedCategory: $selectedCategory,
                isInnerVaultActive: isInnerVaultActive,
                categoryCounts: categoryCounts,
                toggleInnerVaultAction: toggleInnerVault,
                importAction: openImportHub,
                profileAction: { showProfileCenter = true }
            )
        } content: {
            ScrollView(.vertical, showsIndicators: true) {
                splitContent
            }
            .background(AppGlassBackground().ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                bottomInsetContent
            }
            .overlay(alignment: .bottomTrailing) {
                albumFilterButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 38)
            }
            .navigationTitle(selectedCategory.title)
            .toolbar {
                splitToolbar
            }
        } detail: {
            VaultDesktopDetailPane(
                item: desktopDetailItem,
                category: selectedCategory,
                count: visibleItems.count,
                isInnerVaultActive: isInnerVaultActive
            )
            .environmentObject(vaultStore)
        }
        .background(AppGlassBackground().ignoresSafeArea())
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VaultHomeHeader(
                selectedCategory: $selectedCategory,
                isInnerVaultActive: isInnerVaultActive,
                profileAction: { showProfileCenter = true },
                importAction: openImportHub,
                toggleInnerVaultAction: toggleInnerVault,
                onTouchZoneFrameChange: { frame in
                    moLayerTouchZoneFrame = frame
                }
            )

            if shouldShowFreeImportLimitBanner {
                FreeImportLimitBanner()
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

            VaultCategorySummaryFooter(category: selectedCategory, count: visibleItems.count)
        }
        .padding()
    }

    private var splitContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldShowFreeImportLimitBanner {
                FreeImportLimitBanner()
            }

            if let progress = importQueue.progress {
                VaultImportProgressBanner(progress: progress)
            }

            ZStack(alignment: .top) {
                splitCategoryContent

                if visibleItems.isEmpty {
                    EmptyCategoryState(category: selectedCategory)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                        .allowsHitTesting(false)
                }
            }

            VaultCategorySummaryFooter(category: selectedCategory, count: visibleItems.count)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var splitCategoryContent: some View {
        if selectedCategory.usesListLayout {
            VaultLinearCategoryList(
                category: selectedCategory,
                items: visibleItems,
                isInnerVaultActive: isInnerVaultActive,
                isSelectionMode: selectionMode,
                selectedItemIds: selectedItemIds,
                enterSelectionAction: enterSelectionMode,
                toggleSelectionAction: toggleSelection,
                openAudio: { desktopDetailItem = $0 },
                openDocument: { desktopDetailItem = $0 },
                openDetails: { desktopDetailItem = $0 },
                deleteItem: { item in
                    Task { await delete(item) }
                }
            )
        } else {
            mediaGridContent
        }
    }

    @ToolbarContentBuilder
    private var splitToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                toggleInnerVault()
            } label: {
                Image(systemName: isInnerVaultActive ? "arrow.uturn.left" : "lock.fill")
            }
            .accessibilityLabel(isInnerVaultActive ? L.string("Restore") : L.string("Mo Layer"))
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                Task { await refreshVaultFromCloud() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(L.string("Refresh"))
            .keyboardShortcut("r", modifiers: .command)

            Button(action: openImportHub) {
                Image(systemName: folderContextStyle.importSystemImage)
            }
            .accessibilityLabel(L.string("Import"))
            .keyboardShortcut("i", modifiers: .command)

            if subscription.canImportAndSync, !selectableVisibleItems.isEmpty {
                Button(action: selectAllVisibleItems) {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel(L.string("Select All"))
                .keyboardShortcut("a", modifiers: .command)
            }

            if folderContextStyle.showsProfileAction {
                Button {
                    showProfileCenter = true
                } label: {
                    Image(systemName: folderContextStyle.profileSystemImage)
                }
                .accessibilityLabel(L.string("Profile"))
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        if selectedCategory.usesListLayout {
            VaultLinearCategoryList(
                category: selectedCategory,
                items: visibleItems,
                isInnerVaultActive: isInnerVaultActive,
                isSelectionMode: selectionMode,
                selectedItemIds: selectedItemIds,
                enterSelectionAction: enterSelectionMode,
                toggleSelectionAction: toggleSelection,
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

    @ViewBuilder
    private var mediaGridContent: some View {
        if selectedCategory == .album {
            AlbumZoomableMediaGrid(
                items: visibleItems,
                scale: mediaGridScaleBinding,
                contentHeight: $albumGridContentHeight,
                isSelectionMode: selectionMode,
                selectedItemIds: selectedItemIds,
                cachedThumbnailProvider: { vaultStore.cachedThumbnail(for: $0) },
                videoDurationProvider: { vaultStore.metadata(for: $0)?.mediaDurationSeconds },
                thumbnailProvider: { await vaultStore.loadThumbnail(for: $0) },
                visibleItemIDsDidChange: { itemIDs in
                    if visibleAlbumItemIDs != itemIDs {
                        visibleAlbumItemIDs = itemIDs
                    }
                },
                openAction: { open($0, in: visibleItems) },
                toggleSelectionAction: toggleSelection,
                enterSelectionAction: enterSelectionMode
            )
            .frame(maxWidth: .infinity, minHeight: 1)
            .frame(height: albumGridContentHeight)
            .task(id: mediaPreviewRepairKey) {
                await repairVisibleMediaPreviewsIfNeeded()
            }
        } else {
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
    }

    @MainActor
    private func repairVisibleMediaPreviewsIfNeeded() async {
        let candidates = mediaPreviewRepairCandidates
        guard !candidates.isEmpty else { return }
        guard !isRepairingMediaPreviews else {
            vaultHomePerformanceLogger.debug("Skipped overlapping media preview repair candidateCount=\(candidates.count, privacy: .public) visibleCount=\(self.visibleItems.count, privacy: .public)")
            return
        }

        isRepairingMediaPreviews = true
        let startedAt = CFAbsoluteTimeGetCurrent()
        vaultHomePerformanceLogger.info("Media preview repair started candidateCount=\(candidates.count, privacy: .public) visibleCount=\(self.visibleItems.count, privacy: .public)")
        defer {
            isRepairingMediaPreviews = false
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if elapsedMs > 100 {
                vaultHomePerformanceLogger.info("Media preview repair finished candidateCount=\(candidates.count, privacy: .public) visibleCount=\(self.visibleItems.count, privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
            }
        }

        let generatedPreviewNeedsSync = await vaultStore.ensureMediaPreviews(
            for: candidates,
            context: modelContext,
            sync: sync,
            syncAfterRepair: subscription.canImportAndSync
        )
        if generatedPreviewNeedsSync {
            await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
        }
    }

    @ViewBuilder
    private var albumFilterButton: some View {
        if selectedCategory == .album {
            let contextStyle = folderContextStyle
            VStack(alignment: .trailing, spacing: 10) {
                if isAlbumFilterPickerPresented {
                    HStack(spacing: 8) {
                        ForEach(AlbumMediaFilter.allCases) { filter in
                            Button {
                                selectAlbumMediaFilter(filter)
                            } label: {
                                Image(systemName: filter == albumMediaFilter ? "checkmark.circle.fill" : filter.systemImage)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(contextStyle.actionForeground)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Circle()
                                            .fill(filter == albumMediaFilter ? contextStyle.actionForeground.opacity(0.16) : Color.clear)
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(filter.title)
                        }
                    }
                    .padding(8)
                    .background(contextStyle.actionBackground)
                    .clipShape(Capsule())
                    .shadow(color: contextStyle.actionForeground.opacity(0.18), radius: 10, y: 5)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
                }

                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        isAlbumFilterPickerPresented.toggle()
                    }
                } label: {
                    Image(systemName: albumMediaFilter.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(contextStyle.actionForeground)
                        .frame(width: 48, height: 48)
                        .background(contextStyle.actionBackground)
                        .clipShape(Circle())
                        .contentShape(Circle())
                        .shadow(color: contextStyle.actionForeground.opacity(0.22), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.string("Filter"))
                .accessibilityValue(albumMediaFilter.title)
            }
            .zIndex(20)
        }
    }

    private func selectAlbumMediaFilter(_ filter: AlbumMediaFilter) {
        if albumMediaFilter != filter {
            if selectionMode || !selectedItemIds.isEmpty {
                clearSelection()
            }
            if peekItem != nil || peekTouchItemId != nil {
                endLightPeek()
            }
            visibleAlbumItemIDs.removeAll()
            albumMediaFilter = filter
        }
        withAnimation(.snappy(duration: 0.14)) {
            isAlbumFilterPickerPresented = false
        }
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
                detailAction: { openDetails(item) },
                isEnabled: !selectionMode
            )
        )
        .modifier(
            VaultMediaGridContextMenu(
                item: item,
                isEnabled: !(item.kind == .livePhoto && !selectionMode),
                canMoveToMoLayer: subscription.canImportAndSync && !isInnerVaultActive,
                canDelete: subscription.canImportAndSync,
                previewAction: { openPreview(item, in: visibleItems) },
                detailAction: { openDetails(item) },
                moveToMoLayerAction: { Task { await moveSingleItemToMoLayer(item) } },
                deleteAction: { Task { await delete(item) } }
            )
        )
    }

    @ViewBuilder
    private var bottomInsetContent: some View {
        VStack(spacing: 8) {
            if selectionMode {
                if let selectionWorkStatusText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text(selectionWorkStatusText)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                VaultSelectionToolbar(
                    selectedCount: selectedItemIds.count,
                    isDeleting: isDeletingSelection,
                    isExporting: isExportingSelection,
                    isSavingToPhotos: isSavingSelectionToPhotos,
                    canDelete: subscription.canImportAndSync,
                    canExport: !selectedVisibleItems.isEmpty,
                    canSaveToPhotos: selectedItemsCanSaveToPhotos,
                    moveTitle: subscription.canImportAndSync ? (isInnerVaultActive ? L.string("Restore") : L.string("Hide")) : nil,
                    moveSystemImage: isInnerVaultActive ? "arrow.uturn.left" : "lock.fill",
                    cancelAction: clearSelection,
                    exportAction: { Task { await exportSelectedItems() } },
                    saveToPhotosAction: { Task { await saveSelectedItemsToPhotos() } },
                    moveAction: { Task { await moveSelectedItemsBetweenSpaces() } },
                    deleteAction: { confirmBulkDelete = true }
                )
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private func presentMoLayerGuideIfNeeded() {
        guard !hasSeenMoLayerGuide else { return }
        showMoLayerGuide = true
    }

    private func completeMoLayerGuide() {
        hasSeenMoLayerGuide = true
        showMoLayerGuide = false
    }

    private func openImportHub() {
        guard canImportVaultItems(count: 1) else {
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
        guard subscription.canEnterVault else {
            showMoLayerProPrompt = true
            return
        }

        let requestedAt = CFAbsoluteTimeGetCurrent()
        let targetCount = activeItems.reduce(0) { count, item in
            count + (item.folderId == VaultStore.innerVaultFolderId ? 1 : 0)
        }
        vaultHomePerformanceLogger.info("Mo Layer enter requested activeItems=\(self.activeItems.count, privacy: .public) currentVisible=\(self.visibleItems.count, privacy: .public) targetSpaceItems=\(targetCount, privacy: .public)")
        Task { @MainActor in
            let folderStartedAt = CFAbsoluteTimeGetCurrent()
            guard await vaultStore.ensureInnerVaultFolder(context: modelContext, sync: sync) != nil else { return }
            let folderMs = (CFAbsoluteTimeGetCurrent() - folderStartedAt) * 1000
            withAnimation(.snappy) {
                clearSelection()
                endLightPeek()
                isInnerVaultActive = true
            }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - requestedAt) * 1000
            vaultHomePerformanceLogger.info("Mo Layer enter committed targetSpaceItems=\(targetCount, privacy: .public) ensureFolderMs=\(String(format: "%.1f", folderMs), privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        let targetCount = activeItems.reduce(0) { count, item in
            count + (item.folderId != VaultStore.innerVaultFolderId ? 1 : 0)
        }
        vaultHomePerformanceLogger.info("Mo Layer exit requested activeItems=\(self.activeItems.count, privacy: .public) currentVisible=\(self.visibleItems.count, privacy: .public) targetSpaceItems=\(targetCount, privacy: .public)")
        withAnimation(.snappy) {
            clearSelection()
            endLightPeek()
            isInnerVaultActive = false
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        vaultHomePerformanceLogger.info("Mo Layer exit committed targetSpaceItems=\(targetCount, privacy: .public) elapsedMs=\(String(format: "%.1f", elapsedMs), privacy: .public)")
    }

    private func handleQuickAction(_ action: QuickAction?) {
        guard let action else { return }
        switch action {
        case .importHub:
            openImportHub()
        case .camera:
            openImportHub()
        case .recorder:
            if canImportVaultItems(count: 1) {
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
            desktopDetailItem = nil
        }
        quickActions.consume(category)
    }

    private func open(_ item: VaultItem, in collection: [VaultItem]) {
        if usesSplitLayout {
            desktopDetailItem = item
            return
        }

        guard item.kind.isPreviewableContent else {
            selectedItem = item
            return
        }
        openPreview(item, in: collection)
    }

    private func openPreview(_ item: VaultItem, in collection: [VaultItem]) {
        guard item.kind.isPreviewableContent else { return }
        if usesSplitLayout {
            desktopDetailItem = item
            return
        }

        previewSelection = MediaPreviewSelection(
            items: collection.filter { $0.kind.isPreviewableContent },
            initialItemId: item.id
        )
    }

    private func openDetails(_ item: VaultItem) {
        if usesSplitLayout {
            desktopDetailItem = item
        } else {
            selectedItem = item
        }
    }

    private func enterSelectionMode(selecting item: VaultItem) {
        guard VaultSelectionPolicy.canSelect(item) else { return }
        endLightPeek()
        withAnimation(.snappy) {
            selectionMode = true
            selectedItemIds.insert(item.id)
        }
    }

    private func toggleSelection(_ item: VaultItem) {
        guard VaultSelectionPolicy.canSelect(item) else { return }
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

    private func selectAllVisibleItems() {
        let selectableItemIds = selectableVisibleItems
            .map(\.id)
        guard !selectableItemIds.isEmpty else { return }

        withAnimation(.snappy) {
            selectionMode = true
            selectedItemIds = Set(selectableItemIds)
        }
        PlatformCapabilities.selectionChanged()
    }

    private func handleSweepSelectionDrag(location: CGPoint, itemFrames: [AnyHashable: CGRect]) {
        guard selectionMode, subscription.canImportAndSync else { return }
        let selectableItems = selectableVisibleItems
        guard !selectableItems.isEmpty else { return }

        let currentItemId = selectableItems.first { item in
            itemFrames[AnyHashable(item.id)]?.insetBy(dx: -8, dy: -8).contains(location) == true
        }?.id

        if sweepSelectionAnchorId == nil {
            guard let currentItemId else { return }
            sweepSelectionAnchorId = currentItemId
            selectedItemIds.insert(currentItemId)
            PlatformCapabilities.selectionChanged()
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
            PlatformCapabilities.selectionChanged()
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
              item.kind == .image || item.kind == .livePhoto,
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
    private func refreshVaultFromCloud() async {
        await vaultStore.syncCloudToLocal(
            context: modelContext,
            sync: sync,
            allowsCloudSync: subscription.canPullFromCloud,
            allowsCloudWrite: subscription.canImportAndSync,
            downloadsOriginals: VaultCloudToLocalSyncPolicy.manualRefreshDownloadsOriginals
        )
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
    private func exportSelectedItems() async {
        guard !isExportingSelection else { return }
        let selectedItems = selectedVisibleItems
        guard !selectedItems.isEmpty else { return }

        isExportingSelection = true
        defer { isExportingSelection = false }
        let urls = await vaultStore.decryptedTemporaryURLs(for: selectedItems, context: modelContext, sync: sync)
        guard !urls.isEmpty else {
            photoSaveAlert = PhotoSaveAlert(
                title: L.string("Unable to Save"),
                message: L.string("No selected files could be exported.")
            )
            clearSelection()
            return
        }
        sharePayload = SharePayload(items: urls)
        clearSelection()
    }

    @MainActor
    private func saveSelectedItemsToPhotos() async {
        guard !isSavingSelectionToPhotos else { return }
        let selectedItems = selectedVisibleItems
        guard selectedItems.contains(where: { PhotoLibraryExportService.canSaveToPhotoLibrary(kind: $0.kind) }) else {
            photoSaveAlert = PhotoSaveAlert(
                title: L.string("Unable to Save"),
                message: L.string("No selected photos or videos could be saved to Photos.")
            )
            return
        }

        withAnimation(.snappy) {
            isSavingSelectionToPhotos = true
        }
        defer {
            withAnimation(.snappy) {
                isSavingSelectionToPhotos = false
            }
        }
        let result = await PhotoLibraryExportService.save(
            items: selectedItems,
            vaultStore: vaultStore,
            context: modelContext,
            sync: sync
        )
        presentPhotoSaveResult(result)
        clearSelection()
    }

    @MainActor
    private func presentPhotoSaveResult(_ result: PhotoLibraryExportResult) {
        switch result {
        case .saved, .savedMultiple:
            showPhotoSaveToast(
                AppToast(
                    title: result.title,
                    message: result.message,
                    systemImage: "checkmark.circle.fill"
                )
            )
        case .partiallySaved, .unsupported, .permissionDenied, .failed:
            photoSaveAlert = PhotoSaveAlert(result: result)
        }
    }

    @MainActor
    private func showPhotoSaveToast(_ toast: AppToast) {
        photoSaveToastDismissTask?.cancel()
        withAnimation(.snappy) {
            photoSaveToast = toast
        }
        photoSaveToastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard photoSaveToast?.id == toast.id else { return }
                withAnimation(.snappy) {
                    photoSaveToast = nil
                }
            }
        }
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
            let didMove = await vaultStore.moveToInnerVault(selectedItems, context: modelContext, sync: sync)
            if didMove {
                VaultHaptics.moLayerTransferSucceeded()
            }
        }
        clearSelection()
    }

    @MainActor
    private func moveSingleItemToMoLayer(_ item: VaultItem) async {
        guard subscription.canImportAndSync else {
            showMembership = true
            return
        }
        guard !isInnerVaultActive else { return }
        let didMove = await vaultStore.moveToInnerVault([item], context: modelContext, sync: sync)
        if didMove {
            VaultHaptics.moLayerTransferSucceeded()
            if desktopDetailItem?.id == item.id {
                desktopDetailItem = nil
            }
        }
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
        case .album:
            albumGridScale
        case .audio:
            audioGridScale
        case .documents, .links:
            documentGridScale
        }
    }

    private func setStoredScale(_ scale: Double, for category: VaultCategory) {
        switch category {
        case .album:
            albumGridScale = scale
        case .audio:
            audioGridScale = scale
        case .documents, .links:
            documentGridScale = scale
        }
    }
}

private struct FreeImportLimitBanner: View {
    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.open.display")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.string("Free import limit reached"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(L.format("You can keep viewing your vault. Open Pro to add more after %d photos, videos, audio, and files.", VaultFreeImportPolicy.freeItemLimit))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VaultSidebarView: View {
    @Binding var selectedCategory: VaultCategory
    let isInnerVaultActive: Bool
    let categoryCounts: [VaultCategory: Int]
    let toggleInnerVaultAction: () -> Void
    let importAction: () -> Void
    let profileAction: () -> Void

    private var folderContextStyle: VaultFolderContextStyle {
        VaultFolderContextStyle(isInnerVaultActive: isInnerVaultActive)
    }

    var body: some View {
        List {
            Section {
                Button(action: toggleInnerVaultAction) {
                    Label(
                        isInnerVaultActive ? L.string("Regular Vault") : L.string("Mo Layer"),
                        systemImage: isInnerVaultActive ? "tray.full" : "lock.fill"
                    )
                }

            }

            Section(L.string("Library")) {
                ForEach(VaultCategory.homeModes) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack {
                            Label(category.title, systemImage: category.icon)
                            Spacer()
                            Text("\(categoryCounts[category] ?? 0)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedCategory == category ? AppTheme.primary.opacity(0.12) : Color.clear)
                }
            }

            Section {
                Button(action: importAction) {
                    Label(L.string("Import"), systemImage: folderContextStyle.importSystemImage)
                }
                if folderContextStyle.showsProfileAction {
                    Button(action: profileAction) {
                        Label(L.string("Profile"), systemImage: folderContextStyle.profileSystemImage)
                    }
                }
            }
        }
        .navigationTitle(L.string("Mo Layer"))
        .scrollContentBackground(.hidden)
        .background(AppGlassBackground().ignoresSafeArea())
    }
}

private struct VaultDesktopDetailPane: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem?
    let category: VaultCategory
    let count: Int
    let isInnerVaultActive: Bool

    var body: some View {
        Group {
            if let item {
                VaultItemDetailView(item: item)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: category.icon)
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 86, height: 86)
                        .background(AppTheme.primary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(category.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(category.summaryText(count: count))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    if isInnerVaultActive {
                        StatusPill(title: L.string("Mo Layer"), systemImage: "lock.fill", tint: AppTheme.primary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
            }
        }
    }
}

private struct VaultImportProgressBanner: View {
    let progress: VaultImportProgress

    var body: some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                VaultImportProgressThumbnail(progress: progress)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.isActive ? L.string("Importing in Background") : L.string("Import Complete"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let currentItem = progress.currentItem, progress.isActive {
                            Text(currentItem.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                        }
                        Text(progress.currentItem?.phaseText ?? progress.statusText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }

                    if progress.isActive {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress.currentItemProgress)
                                .progressViewStyle(.linear)
                                .tint(AppTheme.primary)
                            HStack {
                                Text(progress.statusText)
                                Spacer(minLength: 8)
                                Text(L.format("%d%%", Int((progress.overallProgress * 100).rounded())))
                            }
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                    } else if progress.importedCount > 0 {
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

private struct VaultImportProgressThumbnail: View {
    let progress: VaultImportProgress

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }

            if !progress.isActive {
                Color.black.opacity(0.18)
                Image(systemName: progress.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(progress.failedCount > 0 ? AppTheme.warning : AppTheme.success)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var image: UIImage? {
        guard let data = progress.currentItem?.thumbnailData else { return nil }
        return UIImage(data: data)
    }

    private var tint: Color {
        guard progress.failedCount == 0 else { return AppTheme.warning }
        return progress.isActive ? AppTheme.primary : AppTheme.success
    }

    private var icon: String {
        if !progress.isActive {
            return progress.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        }
        switch progress.currentItem?.kind {
        case .image:
            return "photo.fill"
        case .livePhoto:
            return "livephoto"
        case .video:
            return "video.fill"
        case .audio:
            return "waveform"
        case .document:
            return "doc.richtext"
        case .archive:
            return "archivebox.fill"
        case .link:
            return "link"
        case .other, nil:
            return "doc"
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

private enum MoLayerTutorialStep: Int, CaseIterable {
    case overview
    case enter
    case save

    var title: String {
        switch self {
        case .overview:
            L.string("What is Mo Layer?")
        case .enter:
            L.string("Enter Mo Layer")
        case .save:
            L.string("Save files to Mo Layer")
        }
    }

    var detail: String {
        switch self {
        case .overview:
            L.string("Mo Layer is a deeper hidden directory inside the real vault. Use it for files that need an extra layer of privacy.")
        case .enter:
            L.string("Tap the blank touch zone between the category title and the profile avatar three times to enter Mo Layer.")
        case .save:
            L.string("Select items in the regular vault and tap Hide, or choose the Mo Layer directory when saving shared files.")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "lock.shield"
        case .enter:
            "hand.tap"
        case .save:
            "lock.doc"
        }
    }
}

enum MoLayerTutorialPracticeResult: Equatable {
    case counting(Int)
    case completed(Int)
}

struct MoLayerTutorialPracticeCounter: Equatable {
    static let requiredTapCount = 3

    private(set) var tapCount = 0

    mutating func recordTap() -> MoLayerTutorialPracticeResult {
        tapCount = min(Self.requiredTapCount, tapCount + 1)
        if tapCount >= Self.requiredTapCount {
            return .completed(tapCount)
        }
        return .counting(tapCount)
    }

    mutating func reset() {
        tapCount = 0
    }
}

private struct MoLayerTutorialOverlay: View {
    let touchZoneFrame: CGRect
    let enterMoLayerAction: () -> Void
    let completeAction: () -> Void
    let dismissAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: MoLayerTutorialStep = .overview
    @State private var practiceCounter = MoLayerTutorialPracticeCounter()

    private var stepIndex: Int { MoLayerTutorialStep.allCases.firstIndex(of: step) ?? 0 }
    private var isLastStep: Bool { stepIndex == MoLayerTutorialStep.allCases.count - 1 }
    private var practiceTapCount: Int { practiceCounter.tapCount }

    var body: some View {
        GeometryReader { proxy in
            let containerFrame = proxy.frame(in: .global)
            let localTouchFrame = localFrame(from: touchZoneFrame, in: containerFrame, fallbackSize: proxy.size)

            ZStack {
                Color.black.opacity(0.54)
                    .ignoresSafeArea()

                if step == .enter {
                    MoLayerSpotlightShape(rect: localTouchFrame.insetBy(dx: -8, dy: -8), cornerRadius: 14)
                        .fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(.black.opacity(0.54))
                        .ignoresSafeArea()

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .background(AppTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(width: max(localTouchFrame.width + 16, 92), height: localTouchFrame.height + 16)
                        .position(x: localTouchFrame.midX, y: localTouchFrame.midY)

                    MoLayerTapIndicator(reduceMotion: reduceMotion)
                        .position(x: localTouchFrame.midX, y: localTouchFrame.midY + 10)

                    Button {
                        recordPracticeTap()
                    } label: {
                        Color.clear
                    }
                    .frame(width: max(localTouchFrame.width + 36, 118), height: localTouchFrame.height + 42)
                    .position(x: localTouchFrame.midX, y: localTouchFrame.midY)
                    .accessibilityLabel(L.string("Practice tapping the Mo Layer entry zone"))
                }

                tutorialCard(localTouchFrame: localTouchFrame, containerSize: proxy.size)
            }
            .animation(.snappy, value: step)
        }
    }

    private func tutorialCard(localTouchFrame: CGRect, containerSize: CGSize) -> some View {
        let cardWidth = min(containerSize.width - 32, 380)
        let yPosition = cardYPosition(for: step, touchFrame: localTouchFrame, containerSize: containerSize)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: step.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.format("Step %d of %d", stepIndex + 1, MoLayerTutorialStep.allCases.count))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primary)
                    Text(step.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if step == .enter {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index < practiceTapCount ? AppTheme.primary : AppTheme.line)
                            .frame(width: 10, height: 10)
                    }

                    Text(L.format("%d of 3 taps", practiceTapCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            HStack(spacing: 10) {
                Button(L.string("Skip")) {
                    completeAction()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                if stepIndex > 0 {
                    Button(L.string("Back")) {
                        goBack()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                }

                Button(isLastStep ? L.string("Done") : L.string("Next")) {
                    advance()
                }
                .buttonStyle(AppButtonStyle())
            }
        }
        .padding(18)
        .frame(width: cardWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.line.opacity(0.8)))
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 14)
        .position(x: containerSize.width / 2, y: yPosition)
    }

    private func localFrame(from globalFrame: CGRect, in containerFrame: CGRect, fallbackSize: CGSize) -> CGRect {
        guard globalFrame != .zero else {
            return CGRect(x: fallbackSize.width * 0.42, y: 88, width: fallbackSize.width * 0.34, height: 44)
        }

        return CGRect(
            x: globalFrame.minX - containerFrame.minX,
            y: globalFrame.minY - containerFrame.minY,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    private func cardYPosition(for step: MoLayerTutorialStep, touchFrame: CGRect, containerSize: CGSize) -> CGFloat {
        switch step {
        case .enter:
            let preferred = touchFrame.maxY + 190
            return min(max(preferred, 250), containerSize.height - 190)
        case .overview, .save:
            return containerSize.height * 0.58
        }
    }

    private func recordPracticeTap() {
        guard step == .enter else { return }
        let result = practiceCounter.recordTap()
        if case .completed = result {
            enterMoLayerAction()
            advance()
        }
    }

    private func goBack() {
        let previousIndex = max(0, stepIndex - 1)
        step = MoLayerTutorialStep.allCases[previousIndex]
        practiceCounter.reset()
    }

    private func advance() {
        guard !isLastStep else {
            completeAction()
            return
        }

        step = MoLayerTutorialStep.allCases[stepIndex + 1]
        practiceCounter.reset()
    }
}

private struct MoLayerTapIndicator: View {
    let reduceMotion: Bool
    @State private var isPressed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.primary, lineWidth: 2)
                .frame(width: 72, height: 72)
                .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.68 : 1.18))
                .opacity(reduceMotion ? 0.65 : (isPressed ? 0.7 : 0.05))

            Capsule()
                .fill(.white)
                .frame(width: 42, height: 58)
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
                .offset(y: reduceMotion ? 0 : (isPressed ? 10 : -6))
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                isPressed = true
            }
        }
    }
}

private struct MoLayerSpotlightShape: Shape {
    let rect: CGRect
    let cornerRadius: CGFloat

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        path.addRect(bounds)
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
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
    var showMoLayerTutorialAction: () -> Void = {}
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

                Section {
                    Button {
                        showMoLayerTutorialAction()
                    } label: {
                        Label(L.string("Mo Layer Tutorial"), systemImage: "hand.tap")
                    }
                    .foregroundStyle(AppTheme.ink)
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
            Link(destination: SubscriptionManager.privacyPolicyURL) {
                Text(ProfileDocumentRoute.privacyPolicy.title)
            }

            Text("·")
                .foregroundStyle(AppTheme.secondaryText.opacity(0.7))

            Link(destination: SubscriptionManager.termsOfUseURL) {
                Text(L.string("Terms of Use"))
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
    case album
    case audio
    case documents
    case links

    var id: String { rawValue }
    static let homeModes: [VaultCategory] = [.album, .audio, .documents]

    var title: String {
        switch self {
        case .album: L.string("Album")
        case .audio: L.string("Audio")
        case .documents: L.string("Files")
        case .links: L.string("Links")
        }
    }

    var icon: String {
        switch self {
        case .album: "photo.on.rectangle"
        case .audio: "waveform"
        case .documents: "doc"
        case .links: "link"
        }
    }

    nonisolated func items(from items: [VaultItem]) -> [VaultItem] {
        items.filter { item in
            guard item.deletedAt == nil else { return false }
            return contains(kind: item.kind)
        }
    }

    func summaryText(count: Int) -> String {
        switch self {
        case .album:
            return L.format("Total %d media items", count)
        case .audio:
            return L.format("Total %d audio files", count)
        case .documents:
            return L.format("Total %d files", count)
        case .links:
            return L.format("%d items", count)
        }
    }

    nonisolated func contains(kind: VaultItemKind) -> Bool {
        switch self {
        case .album:
            return kind == .image || kind == .livePhoto || kind == .video
        case .audio:
            return kind == .audio
        case .documents:
            return kind == .document || kind == .archive || kind == .other
        case .links:
            return kind == .link
        }
    }
}

private enum AlbumMediaFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L.string("All")
        case .photos: L.string("Photos")
        case .videos: L.string("Videos")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .photos: "photo.on.rectangle"
        case .videos: "video.fill"
        }
    }

    func items(from items: [VaultItem]) -> [VaultItem] {
        switch self {
        case .all:
            return items
        case .photos:
            return items.filter { $0.kind == .image || $0.kind == .livePhoto }
        case .videos:
            return items.filter { $0.kind == .video }
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
                    isInnerVaultActive: false,
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
            DocumentDetailPreviewView(item: item, isInnerVaultActive: false)
        }
        .fullScreenCover(item: $previewSelection) { selection in
            VaultMediaPreviewView(
                items: selection.items,
                initialItemId: selection.initialItemId,
                isInnerVaultActive: false
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

    private var thumbnail: some View {
        ZStack(alignment: .topLeading) {
            if let image = vaultStore.thumbnail(for: item) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.primary.opacity(0.1))
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary)
            }

            if item.kind == .livePhoto {
                Image(systemName: "livephoto")
                    .font(.caption2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                    .padding(5)
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
    let isInnerVaultActive: Bool
    var isSelectionMode = false
    var selectedItemIds: Set<String> = []
    var enterSelectionAction: (VaultItem) -> Void = { _ in }
    var toggleSelectionAction: (VaultItem) -> Void = { _ in }
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
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedItemIds.contains(item.id),
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
                        canMoveToMoLayer: subscription.canImportAndSync && !isInnerVaultActive,
                        moveToMoLayerAction: { Task { await moveToMoLayer(item) } },
                        canDelete: subscription.canImportAndSync,
                        deleteAction: { deleteItem(item) },
                        selectionAction: { handleSelection(for: item) }
                    )
                } else {
                    DocumentListRow(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedItemIds.contains(item.id),
                        openAction: {
                            stopAudioPlayback()
                            openDocument(item)
                        },
                        detailAction: { openDetails(item) },
                        shareAction: { Task { await share(item) } },
                        canRename: subscription.canImportAndSync,
                        renameAction: { renameItem = item },
                        canMoveToMoLayer: subscription.canImportAndSync && !isInnerVaultActive,
                        moveToMoLayerAction: { Task { await moveToMoLayer(item) } },
                        canDelete: subscription.canImportAndSync,
                        deleteAction: { deleteItem(item) },
                        selectionAction: { handleSelection(for: item) }
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
    private func handleSelection(for item: VaultItem) {
        guard VaultSelectionPolicy.canSelect(item) else { return }
        stopAudioPlayback()
        if isSelectionMode {
            toggleSelectionAction(item)
        } else {
            enterSelectionAction(item)
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

    @MainActor
    private func moveToMoLayer(_ item: VaultItem) async {
        guard subscription.canImportAndSync, !isInnerVaultActive else { return }
        stopAudioPlayback()
        let didMove = await vaultStore.moveToInnerVault([item], context: modelContext, sync: sync)
        if didMove {
            VaultHaptics.moLayerTransferSucceeded()
        }
    }
}

private struct AudioListRow: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem
    let isSelectionMode: Bool
    let isSelected: Bool
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
    let canMoveToMoLayer: Bool
    let moveToMoLayerAction: () -> Void
    let canDelete: Bool
    let deleteAction: () -> Void
    let selectionAction: () -> Void

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                VaultSelectionCheckbox(isSelected: isSelected)
                    .transition(.scale.combined(with: .opacity))
            }

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
            .allowsHitTesting(!isSelectionMode)
            .opacity(isSelectionMode ? 0.58 : 1)

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

            if !isSelectionMode {
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
                    if canMoveToMoLayer {
                        Button(action: moveToMoLayerAction) {
                            Label(L.string("Send to Mo Layer"), systemImage: "lock.fill")
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
        }
        .padding(12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? AppTheme.primary : AppTheme.line, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                selectionAction()
            } else {
                openAction()
            }
        }
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 18) {
            if !isSelectionMode {
                selectionAction()
            }
        }
        .animation(.smooth(duration: 0.18), value: isPlaying)
        .animation(.smooth(duration: 0.12), value: currentTime)
        .animation(.smooth(duration: 0.16), value: isSelectionMode)
        .animation(.smooth(duration: 0.16), value: isSelected)
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
    let isSelectionMode: Bool
    let isSelected: Bool
    let openAction: () -> Void
    let detailAction: () -> Void
    let shareAction: () -> Void
    let canRename: Bool
    let renameAction: () -> Void
    let canMoveToMoLayer: Bool
    let moveToMoLayerAction: () -> Void
    let canDelete: Bool
    let deleteAction: () -> Void
    let selectionAction: () -> Void

    private var metadata: VaultMetadata? {
        vaultStore.metadata(for: item)
    }

    private var descriptor: FileFormatDescriptor {
        FileFormatDescriptor(metadata: metadata, kind: item.kind)
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                VaultSelectionCheckbox(isSelected: isSelected)
                    .transition(.scale.combined(with: .opacity))
            }

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

            if !isSelectionMode {
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
                    if canMoveToMoLayer {
                        Button(action: moveToMoLayerAction) {
                            Label(L.string("Send to Mo Layer"), systemImage: "lock.fill")
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
        }
        .padding(12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? AppTheme.primary : AppTheme.line, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                selectionAction()
            } else {
                openAction()
            }
        }
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 18) {
            if !isSelectionMode {
                selectionAction()
            }
        }
        .animation(.smooth(duration: 0.16), value: isSelectionMode)
        .animation(.smooth(duration: 0.16), value: isSelected)
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
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem

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
                    colors: [.clear, .black.opacity(kind == .video ? 0.34 : 0.18)],
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

private struct VaultMediaGridContextMenu: ViewModifier {
    let item: VaultItem
    let isEnabled: Bool
    let canMoveToMoLayer: Bool
    let canDelete: Bool
    let previewAction: () -> Void
    let detailAction: () -> Void
    let moveToMoLayerAction: () -> Void
    let deleteAction: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                if item.kind.isPreviewableContent {
                    Button(action: previewAction) {
                        Label(L.string("Preview"), systemImage: "rectangle.expand.vertical")
                    }
                }

                Button(action: detailAction) {
                    Label(L.string("Details"), systemImage: "info.circle")
                }

                if canMoveToMoLayer {
                    Button(action: moveToMoLayerAction) {
                        Label(L.string("Hide"), systemImage: "lock.fill")
                    }
                }

                if canDelete {
                    Button(role: .destructive, action: deleteAction) {
                        Label(L.string("Delete"), systemImage: "trash")
                    }
                }
            }
        } else {
            content
        }
    }
}

private struct LivePhotoPlaybackView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playbackTrigger: Int
    let playbackStyle: PHLivePhotoViewPlaybackStyle

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        if playbackTrigger > 0, context.coordinator.lastPlaybackTrigger != playbackTrigger {
            context.coordinator.lastPlaybackTrigger = playbackTrigger
            uiView.startPlayback(with: playbackStyle)
        }
    }

    final class Coordinator {
        var lastPlaybackTrigger = 0
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
    let isInnerVaultActive: Bool
    @State private var selectedId: String
    @State private var scrollPosition: String?
    @State private var previewItems: [VaultItem]
    @State private var sharePayload: SharePayload?
    @State private var detailItem: VaultItem?
    @State private var isPreparingShare = false
    @State private var isSavingToPhotos = false
    @State private var isMovingToMoLayer = false
    @State private var isDeletingSelectedItem = false
    @State private var photoSaveAlert: PhotoSaveAlert?
    @State private var originalScreenBrightness: CGFloat?
    @State private var livePhotoPlaybackTriggers: [String: Int] = [:]

    init(items: [VaultItem], initialItemId: String, isInnerVaultActive: Bool) {
        self.items = items
        self.initialItemId = initialItemId
        self.isInnerVaultActive = isInnerVaultActive
        _selectedId = State(initialValue: initialItemId)
        _scrollPosition = State(initialValue: initialItemId)
        _previewItems = State(initialValue: items)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                            FullscreenMediaPage(
                                item: item,
                                loadMode: FullscreenMediaLoadingPolicy.loadMode(
                                    itemIndex: index,
                                    selectedIndex: selectedIndex,
                                    itemKind: item.kind
                                ),
                                livePhotoPlaybackTrigger: livePhotoPlaybackTriggers[item.id, default: 0]
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .onChange(of: scrollPosition) { _, newValue in
                    guard let newValue,
                          previewItems.contains(where: { $0.id == newValue }) else { return }
                    selectedId = newValue
                }
                .onChange(of: selectedId) { _, newValue in
                    if scrollPosition != newValue {
                        scrollPosition = newValue
                    }
                }
            }
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

                        if subscription.canImportAndSync && !isInnerVaultActive {
                            Button {
                                Task { await moveSelectedItemToMoLayer() }
                            } label: {
                                Label(L.string("Send to Mo Layer"), systemImage: "lock.fill")
                            }
                            .disabled(isMovingToMoLayer)
                        }

                        if subscription.canImportAndSync {
                            Button(role: .destructive) {
                                Task { await deleteSelectedItem() }
                            } label: {
                                Label(L.string("Delete"), systemImage: "trash")
                            }
                            .disabled(isDeletingSelectedItem)
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

            if selectedItem?.kind == .livePhoto {
                livePhotoPlaybackButton
                    .padding(.trailing, 18)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
            if originalScreenBrightness == nil {
                originalScreenBrightness = UIScreen.main.brightness
            }
            MediaPreviewAudioSession.activateForPlayback()
        }
        .onChange(of: selectedId) { _, newValue in
            livePhotoPlaybackTriggers[newValue] = 0
        }
        .onDisappear {
            if let originalScreenBrightness {
                UIScreen.main.brightness = originalScreenBrightness
            }
            MediaPreviewAudioSession.deactivate()
        }
    }

    private var selectedItem: VaultItem? {
        previewItems.first { $0.id == selectedId }
    }

    private var selectedIndex: Int? {
        previewItems.firstIndex { $0.id == selectedId }
    }

    private var canSaveSelectedItemToPhotos: Bool {
        selectedItem.map { PhotoLibraryExportService.canSaveToPhotoLibrary(kind: $0.kind) } ?? false
    }

    private var livePhotoPlaybackButton: some View {
        Button {
            livePhotoPlaybackTriggers[selectedId, default: 0] += 1
        } label: {
            Image(systemName: "livephoto.play")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.42))
                .clipShape(Circle())
        }
        .accessibilityLabel(L.string("Play Live Photo"))
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
        guard subscription.canImportAndSync, !isDeletingSelectedItem else { return }
        guard let selectedItem else { return }
        isDeletingSelectedItem = true
        defer { isDeletingSelectedItem = false }

        let nextSelection = previewItems.first { $0.id != selectedItem.id }?.id
        await vaultStore.deleteImmediately(selectedItem, context: modelContext, sync: sync)
        if let nextSelection {
            selectedId = nextSelection
            scrollPosition = nextSelection
            await Task.yield()
            previewItems.removeAll { $0.id == selectedItem.id }
        } else {
            dismiss()
            previewItems.removeAll { $0.id == selectedItem.id }
        }
    }

    @MainActor
    private func moveSelectedItemToMoLayer() async {
        guard subscription.canImportAndSync, !isInnerVaultActive, !isMovingToMoLayer else { return }
        guard let selectedItem else { return }
        isMovingToMoLayer = true
        defer { isMovingToMoLayer = false }

        let nextSelection = previewItems.first { $0.id != selectedItem.id }?.id
        let didMove = await vaultStore.moveToInnerVault([selectedItem], context: modelContext, sync: sync)
        guard didMove else { return }
        VaultHaptics.moLayerTransferSucceeded()
        if let nextSelection {
            selectedId = nextSelection
            scrollPosition = nextSelection
            await Task.yield()
            previewItems.removeAll { $0.id == selectedItem.id }
        } else {
            dismiss()
            previewItems.removeAll { $0.id == selectedItem.id }
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

                if let location = metadata?.captureLocation {
                    Section(L.string("Location")) {
                        NavigationLink {
                            VaultLocationMapView(
                                location: location,
                                title: metadata?.originalName ?? L.string("Private Item")
                            )
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.resolvedAddress ?? location.coordinateText)
                                        .foregroundStyle(AppTheme.ink)
                                    Text(L.string("View on Map"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            } icon: {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        detailRow(L.string("Address"), location.resolvedAddress)
                        detailRow(L.string("Captured"), location.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        if let accuracy = location.horizontalAccuracy {
                            detailRow(L.string("Accuracy"), L.format("Within %.0f m", accuracy))
                        }
                        if let altitude = location.altitude {
                            detailRow(L.string("Altitude"), L.format("%.0f m", altitude))
                        }
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
                    if item.assetState == .local, VaultFileStore.fileExists(path: item.encryptedFilePath) {
                        Button {
                            _ = vaultStore.releaseLocalOriginal(for: item, context: modelContext)
                        } label: {
                            Label(L.string("Release Local Space"), systemImage: "icloud.and.arrow.up")
                        }
                    }
                    Text(L.string("Items are encrypted on this device before optional iCloud sync."))
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

private struct VaultLocationMapView: View {
    let location: VaultCaptureLocation
    let title: String

    private var coordinate: CLLocationCoordinate2D {
        let mapCoordinate = VaultMapCoordinatePolicy.mapCoordinate(
            latitude: location.latitude,
            longitude: location.longitude
        )
        return CLLocationCoordinate2D(latitude: mapCoordinate.latitude, longitude: mapCoordinate.longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    var body: some View {
        List {
            Section {
                Map(position: .constant(.region(region))) {
                    Marker(title, coordinate: coordinate)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section(L.string("Location")) {
                detailRow(L.string("Address"), location.resolvedAddress)
                detailRow(L.string("Coordinates"), location.coordinateText)
                detailRow(L.string("Captured"), location.capturedAt.formatted(date: .abbreviated, time: .shortened))
                if let accuracy = location.horizontalAccuracy {
                    detailRow(L.string("Accuracy"), L.format("Within %.0f m", accuracy))
                }
                if let altitude = location.altitude {
                    detailRow(L.string("Altitude"), L.format("%.0f m", altitude))
                }
                Button {
                    openInMaps()
                } label: {
                    Label(L.string("Open in Apple Maps"), systemImage: "map")
                }
            }
        }
        .navigationTitle(L.string("Map"))
        .navigationBarTitleDisplayMode(.inline)
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

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = title
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: region.span)
        ])
    }
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
    @EnvironmentObject private var subscription: SubscriptionManager
    let item: VaultItem
    let isInnerVaultActive: Bool
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
                        if subscription.canImportAndSync && !isInnerVaultActive {
                            Button {
                                Task { await moveItemToMoLayer() }
                            } label: {
                                Label(L.string("Send to Mo Layer"), systemImage: "lock.fill")
                            }
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

    @MainActor
    private func moveItemToMoLayer() async {
        guard subscription.canImportAndSync, !isInnerVaultActive else { return }
        let didMove = await vaultStore.moveToInnerVault([item], context: modelContext, sync: sync)
        if didMove {
            VaultHaptics.moLayerTransferSucceeded()
            dismiss()
        }
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

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(result: PhotoLibraryExportResult) {
        self.title = result.title
        self.message = result.message
    }
}

private struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
}

private struct AppToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(toast.message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.line.opacity(0.65)))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        .frame(maxWidth: 360)
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

    static func makePlayer(for url: URL, kind: VaultItemKind) -> AVPlayer {
        let item = AVPlayerItem(url: url)
        if kind == .video {
            item.preferredForwardBufferDuration = 5
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        }
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        configure(player)
        return player
    }
}

private struct VaultPeekPreviewOverlay: View {
    let item: VaultItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea()

            FullscreenMediaPage(item: item, loadMode: .original, livePhotoPlaybackTrigger: 0)
                .ignoresSafeArea()
        }
    }
}

enum FullscreenMediaLoadMode: String, Equatable {
    case none
    case thumbnail
    case original
}

enum FullscreenMediaLoadingPolicy {
    nonisolated static func shouldLoadOriginal(isSelected: Bool) -> Bool {
        isSelected
    }

    nonisolated static func loadMode(
        itemIndex: Int,
        selectedIndex: Int?,
        itemKind: VaultItemKind,
        preloadRadius: Int = 1
    ) -> FullscreenMediaLoadMode {
        guard let selectedIndex else { return .none }
        if itemIndex == selectedIndex {
            return .original
        }
        guard abs(itemIndex - selectedIndex) <= max(preloadRadius, 0) else {
            return .none
        }
        return itemKind.isStillImageMedia ? .original : .thumbnail
    }
}

enum FullscreenMediaStagingPolicy {
    nonisolated static func shouldShowThumbnailBeforeOriginal(kind: VaultItemKind) -> Bool {
        !kind.isStillImageMedia
    }
}

private struct FullscreenMediaPage: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "MediaPreview")
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var sync: CloudKitSyncService
    let item: VaultItem
    let loadMode: FullscreenMediaLoadMode
    let livePhotoPlaybackTrigger: Int
    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var player: AVPlayer?
    @State private var previewURL: URL?
    @State private var previewTitle = ""
    @State private var isLoading = true
    @State private var playbackReloadGeneration = 0

    private var isSelected: Bool {
        loadMode == .original
    }

    var body: some View {
        ZStack {
            if item.kind == .livePhoto, let livePhoto {
                LivePhotoPlaybackView(
                    livePhoto: livePhoto,
                    playbackTrigger: livePhotoPlaybackTrigger,
                    playbackStyle: .full
                )
                    .ignoresSafeArea()
            } else if item.kind == .video, let player {
                ZoomableVideoPreview(
                    player: player,
                    reloadAction: { playbackReloadGeneration += 1 }
                )
                    .onAppear { updateVideoPlayback() }
                    .onChange(of: isSelected) { _, _ in updateVideoPlayback() }
                    .onDisappear { player.pause() }
            } else if let image {
                ZoomableImagePreview(image: image)
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
        .task(id: "\(item.id):\(loadMode.rawValue):\(playbackReloadGeneration)") {
            switch loadMode {
            case .original:
                await loadOriginal()
            case .thumbnail:
                await loadThumbnailOnly()
            case .none:
                unload()
            }
        }
    }

    @MainActor
    private func unload() {
        isLoading = false
        image = nil
        livePhoto = nil
        player?.pause()
        player = nil
        previewURL = nil
        previewTitle = ""
    }

    @MainActor
    private func loadThumbnailOnly() async {
        isLoading = true
        livePhoto = nil
        player?.pause()
        player = nil
        previewURL = nil
        previewTitle = vaultStore.metadata(for: item)?.originalName ?? L.string("Private Item")
        image = item.kind.isVisualMedia ? await vaultStore.loadThumbnail(for: item) : nil
        guard !Task.isCancelled else { return }
        isLoading = false
    }

    @MainActor
    private func loadOriginal() async {
        isLoading = true
        livePhoto = nil
        player?.pause()
        player = nil
        previewURL = nil
        previewTitle = vaultStore.metadata(for: item)?.originalName ?? L.string("Private Item")
        if FullscreenMediaStagingPolicy.shouldShowThumbnailBeforeOriginal(kind: item.kind),
           item.kind.isVisualMedia {
            image = await vaultStore.loadThumbnail(for: item)
        }
        guard !Task.isCancelled else { return }
        defer { isLoading = false }

        if item.kind == .livePhoto {
            let loadedLivePhoto = await makeLivePhoto(for: item, vaultStore: vaultStore, context: modelContext, sync: sync)
            guard !Task.isCancelled else { return }
            livePhoto = loadedLivePhoto
            return
        }

        let url: URL
        do {
            url = try await vaultStore.decryptedTemporaryURL(for: item, context: modelContext, sync: sync)
        } catch {
            Self.logger.error("Preview decrypt failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }
        if item.kind == .image, let loaded = await Self.decodedImage(at: url) {
            guard !Task.isCancelled else { return }
            image = loaded
        } else if item.kind == .video || item.kind == .audio {
            previewURL = url
            let mediaPlayer = MediaPreviewAudioSession.makePlayer(for: url, kind: item.kind)
            player = mediaPlayer
            updateVideoPlayback(for: mediaPlayer)
        } else if item.kind.isDocumentPreview {
            previewURL = url
        } else {
            Self.logger.error("Preview data could not decode for item \(item.id, privacy: .public), kind \(item.kind.rawValue, privacy: .public)")
        }
    }

    private static func decodedImage(at url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                }
            }
        }
    }

    private func updateVideoPlayback(for mediaPlayer: AVPlayer? = nil) {
        guard item.kind == .video else { return }
        let currentPlayer = mediaPlayer ?? player
        guard let currentPlayer else { return }
        if mediaPlayer != nil {
            MediaPreviewAudioSession.configure(currentPlayer)
        }
        if !isSelected {
            currentPlayer.pause()
        }
    }
}

enum VideoPlayerAdjustmentKind: Equatable {
    case brightness
    case volume
}

enum VideoPlayerGesturePolicy {
    private nonisolated static let minimumMovement: CGFloat = 12

    nonisolated static func adjustment(
        startX: CGFloat,
        containerWidth: CGFloat,
        translation: CGSize,
        scale: CGFloat
    ) -> VideoPlayerAdjustmentKind? {
        guard scale <= 1.001,
              containerWidth > 0,
              abs(translation.height) >= minimumMovement,
              abs(translation.height) > abs(translation.width) else {
            return nil
        }
        return startX < containerWidth / 2 ? .brightness : .volume
    }

    nonisolated static func adjustedValue(
        startingValue: Double,
        verticalTranslation: CGFloat,
        containerHeight: CGFloat,
        range: ClosedRange<Double>
    ) -> Double {
        let effectiveHeight = max(containerHeight, 1)
        let delta = -Double(verticalTranslation / effectiveHeight)
        return min(max(startingValue + delta, range.lowerBound), range.upperBound)
    }
}

enum VideoPlayerIdleTimerPolicy {
    nonisolated static func shouldDisableIdleTimer(isPlaying: Bool, isVisible: Bool) -> Bool {
        isPlaying && isVisible
    }
}

private struct ZoomableVideoPreview: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy",
        category: "VideoPlayer"
    )
    private static let controlsAutoHideDelay: UInt64 = 3_000_000_000

    let player: AVPlayer
    let reloadAction: () -> Void
    @State private var scale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @State private var controlsVisible = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var isPlaying = false
    @State private var didReachEnd = false
    @State private var playbackFailed = false
    @State private var isVisible = false
    @State private var isMuted = false
    @State private var volume: Double = 1
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var activeAdjustment: VideoPlayerAdjustmentKind?
    @State private var adjustmentStartValue: Double?
    @State private var adjustmentIndicator: VideoPlayerAdjustmentIndicatorState?
    @State private var timeObserver: Any?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var hideAdjustmentTask: Task<Void, Never>?
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

            ZStack {
                PlayerLayerView(player: player)
                    .scaleEffect(displayScale)
                    .offset(offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(zoomGesture(containerSize: proxy.size))
                    .simultaneousGesture(dragGesture(containerSize: proxy.size))
                    .simultaneousGesture(adjustmentGesture(containerSize: proxy.size))
                    .simultaneousGesture(tapGesture)

                if controlsVisible {
                    VideoPlayerControlsOverlay(
                        isPlaying: isPlaying,
                        didReachEnd: didReachEnd,
                        playbackFailed: playbackFailed,
                        currentTime: currentTime,
                        duration: duration,
                        isMuted: isMuted,
                        scrubTime: $scrubTime,
                        isScrubbing: $isScrubbing,
                        playPauseAction: togglePlayback,
                        retryAction: retryPlayback,
                        backwardAction: { jump(by: -10) },
                        forwardAction: { jump(by: 10) },
                        scrubEditingChanged: scrubEditingChanged,
                        scrubChanged: updateScrubTime,
                        muteAction: toggleMute,
                        interactionAction: showControlsAndScheduleHide
                    )
                    .transition(.opacity)
                    .allowsHitTesting(true)
                }

                if let adjustmentIndicator {
                    VideoPlayerAdjustmentIndicator(state: adjustmentIndicator)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            isVisible = true
            installTimeObserver()
            syncPlayerState()
            updateIdleTimer()
            showControlsAndScheduleHide()
        }
        .onDisappear {
            player.pause()
            isPlaying = false
            isVisible = false
            updateIdleTimer()
            removeTimeObserver()
            hideControlsTask?.cancel()
            hideAdjustmentTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === player.currentItem else { return }
            didReachEnd = true
            isPlaying = false
            currentTime = duration
            updateIdleTimer()
            showControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled)) { notification in
            guard notification.object as? AVPlayerItem === player.currentItem else { return }
            Self.logger.notice("Video playback stalled")
            syncPlayerState()
            showControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === player.currentItem else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            Self.logger.error(
                "Video playback failed domain=\(error?.domain ?? "unknown", privacy: .public) code=\(error?.code ?? -1, privacy: .public)"
            )
            player.pause()
            playbackFailed = true
            isPlaying = false
            updateIdleTimer()
            showControls()
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

    private var tapGesture: some Gesture {
        ExclusiveGesture(TapGesture(count: 2), TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    withAnimation(.snappy(duration: 0.2)) {
                        if scale > 1 {
                            scale = 1
                            committedOffset = .zero
                        } else {
                            scale = 2.5
                        }
                    }
                    showControlsAndScheduleHide()
                case .second:
                    toggleControls()
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

    private func adjustmentGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let kind = activeAdjustment ?? VideoPlayerGesturePolicy.adjustment(
                    startX: value.startLocation.x,
                    containerWidth: containerSize.width,
                    translation: value.translation,
                    scale: displayScale
                ) else { return }

                if activeAdjustment == nil {
                    activeAdjustment = kind
                    adjustmentStartValue = kind == .brightness ? brightness : volume
                    hideAdjustmentTask?.cancel()
                }
                guard let startingValue = adjustmentStartValue else { return }

                let range: ClosedRange<Double> = kind == .brightness ? 0.05...1 : 0...1
                let newValue = VideoPlayerGesturePolicy.adjustedValue(
                    startingValue: startingValue,
                    verticalTranslation: value.translation.height,
                    containerHeight: containerSize.height,
                    range: range
                )
                applyAdjustment(kind, value: newValue)
            }
            .onEnded { _ in
                finishAdjustment()
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

    private func installTimeObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                currentTime = max(seconds, 0)
            }
            syncPlayerState()
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func syncPlayerState() {
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        let wasPlaying = isPlaying
        isPlaying = player.timeControlStatus == .playing
        isMuted = player.isMuted
        volume = Double(player.volume)
        brightness = Double(UIScreen.main.brightness)
        updateIdleTimer()
        if isPlaying && !wasPlaying {
            scheduleControlsAutoHide()
        }
    }

    private func togglePlayback() {
        guard !playbackFailed else {
            retryPlayback()
            return
        }
        MediaPreviewAudioSession.activateForPlayback()
        showControlsAndScheduleHide()
        if didReachEnd {
            didReachEnd = false
            currentTime = 0
            scrubTime = 0
            player.seek(to: .zero)
        }

        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateIdleTimer()
    }

    private func retryPlayback() {
        player.pause()
        playbackFailed = false
        isPlaying = false
        updateIdleTimer()
        reloadAction()
    }

    private func jump(by seconds: Double) {
        let targetTime = clampedTime(currentTime + seconds)
        seek(to: targetTime, resumePlayback: player.timeControlStatus == .playing)
        currentTime = targetTime
        showControlsAndScheduleHide()
    }

    private func scrubEditingChanged(_ isEditing: Bool) {
        if isEditing {
            wasPlayingBeforeScrub = player.timeControlStatus == .playing
            isScrubbing = true
            scrubTime = currentTime
            player.pause()
            showControls()
        } else {
            let targetTime = clampedTime(scrubTime)
            isScrubbing = false
            currentTime = targetTime
            seek(to: targetTime, resumePlayback: wasPlayingBeforeScrub)
            showControlsAndScheduleHide()
        }
    }

    private func updateScrubTime(_ value: Double) {
        scrubTime = clampedTime(value)
        currentTime = scrubTime
        showControls()
    }

    private func seek(to seconds: Double, resumePlayback: Bool) {
        didReachEnd = false
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                currentTime = seconds
                if resumePlayback {
                    MediaPreviewAudioSession.activateForPlayback()
                    player.play()
                    isPlaying = true
                    updateIdleTimer()
                }
            }
        }
    }

    private func toggleMute() {
        showControlsAndScheduleHide()
        if isMuted {
            if volume <= 0 {
                setVolume(1)
            }
            player.isMuted = false
            isMuted = false
        } else {
            player.isMuted = true
            isMuted = true
        }
    }

    private func setVolume(_ value: Double, schedulesControls: Bool = true) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        player.volume = Float(clamped)
        player.isMuted = clamped == 0
        isMuted = player.isMuted
        if schedulesControls {
            showControlsAndScheduleHide()
        }
    }

    private func setBrightness(_ value: Double, schedulesControls: Bool = true) {
        let clamped = min(max(value, 0.05), 1)
        brightness = clamped
        UIScreen.main.brightness = CGFloat(clamped)
        if schedulesControls {
            showControlsAndScheduleHide()
        }
    }

    private func applyAdjustment(_ kind: VideoPlayerAdjustmentKind, value: Double) {
        if kind == .brightness {
            setBrightness(value, schedulesControls: false)
        } else {
            setVolume(value, schedulesControls: false)
        }
        withAnimation(.easeOut(duration: 0.12)) {
            adjustmentIndicator = VideoPlayerAdjustmentIndicatorState(kind: kind, value: value)
        }
    }

    private func finishAdjustment() {
        guard adjustmentIndicator != nil else { return }
        activeAdjustment = nil
        adjustmentStartValue = nil
        hideAdjustmentTask?.cancel()
        hideAdjustmentTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                adjustmentIndicator = nil
            }
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleControlsAutoHide()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func showControls() {
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible = true
        }
        hideControlsTask?.cancel()
    }

    private func showControlsAndScheduleHide() {
        showControls()
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        hideControlsTask?.cancel()
        guard isPlaying, !isScrubbing, !didReachEnd, !playbackFailed else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.controlsAutoHideDelay)
            guard !Task.isCancelled, isPlaying, !isScrubbing, !didReachEnd, !playbackFailed else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }

    private func clampedTime(_ value: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return max(value, 0) }
        return min(max(value, 0), duration)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = VideoPlayerIdleTimerPolicy.shouldDisableIdleTimer(
            isPlaying: isPlaying,
            isVisible: isVisible
        )
    }
}

private struct VideoPlayerAdjustmentIndicatorState: Equatable {
    let kind: VideoPlayerAdjustmentKind
    let value: Double

    var systemImage: String {
        switch kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if value <= 0 {
                return "speaker.slash.fill"
            }
            if value < 0.5 {
                return "speaker.wave.1.fill"
            }
            return "speaker.wave.3.fill"
        }
    }

    var percentageText: String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct VideoPlayerAdjustmentIndicator: View {
    let state: VideoPlayerAdjustmentIndicatorState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: state.systemImage)
                .font(.system(size: 30, weight: .semibold))

            Text(state.percentageText)
                .font(.headline.monospacedDigit())
        }
        .foregroundStyle(.white)
        .frame(width: 112, height: 104)
        .background(.black.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.string(state.kind == .brightness ? "Brightness" : "Volume"))
        .accessibilityValue(state.percentageText)
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerLayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct VideoPlayerControlsOverlay: View {
    let isPlaying: Bool
    let didReachEnd: Bool
    let playbackFailed: Bool
    let currentTime: Double
    let duration: Double
    let isMuted: Bool
    @Binding var scrubTime: Double
    @Binding var isScrubbing: Bool
    let playPauseAction: () -> Void
    let retryAction: () -> Void
    let backwardAction: () -> Void
    let forwardAction: () -> Void
    let scrubEditingChanged: (Bool) -> Void
    let scrubChanged: (Double) -> Void
    let muteAction: () -> Void
    let interactionAction: () -> Void

    private var displayedTime: Double {
        isScrubbing ? scrubTime : currentTime
    }

    var body: some View {
        ZStack {
            VideoPlayerTransportControls(
                isPlaying: isPlaying,
                didReachEnd: didReachEnd,
                playbackFailed: playbackFailed,
                playPauseAction: playPauseAction,
                retryAction: retryAction,
                backwardAction: backwardAction,
                forwardAction: forwardAction,
                interactionAction: interactionAction
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack {
                Spacer()

                HStack(spacing: 8) {
                    VideoPlayerProgressControl(
                        displayedTime: displayedTime,
                        duration: duration,
                        scrubTime: $scrubTime,
                        scrubChanged: scrubChanged,
                        scrubEditingChanged: scrubEditingChanged
                    )

                    controlButton(
                        systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        accessibilityLabel: L.string(isMuted ? "Unmute" : "Mute"),
                        action: muteAction
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 34)
            }
        }
    }

    private func controlButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button {
            interactionAction()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct VideoPlayerTransportControls: View {
    let isPlaying: Bool
    let didReachEnd: Bool
    let playbackFailed: Bool
    let playPauseAction: () -> Void
    let retryAction: () -> Void
    let backwardAction: () -> Void
    let forwardAction: () -> Void
    let interactionAction: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            transportButton(
                systemImage: "gobackward.10",
                accessibilityLabel: L.string("Back 10 Seconds"),
                size: 52,
                action: backwardAction
            )

            transportButton(
                systemImage: primarySystemImage,
                accessibilityLabel: primaryAccessibilityLabel,
                size: 66,
                action: playbackFailed ? retryAction : playPauseAction
            )

            transportButton(
                systemImage: "goforward.10",
                accessibilityLabel: L.string("Forward 10 Seconds"),
                size: 52,
                action: forwardAction
            )
        }
    }

    private var primarySystemImage: String {
        if playbackFailed {
            return "arrow.clockwise"
        }
        if didReachEnd {
            return "gobackward"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    private var primaryAccessibilityLabel: String {
        if playbackFailed {
            return L.string("Retry Playback")
        }
        if didReachEnd {
            return L.string("Replay")
        }
        return L.string(isPlaying ? "Pause" : "Play")
    }

    private func transportButton(
        systemImage: String,
        accessibilityLabel: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            interactionAction()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size == 66 ? 27 : 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.56))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct VideoPlayerProgressControl: View {
    let displayedTime: Double
    let duration: Double
    @Binding var scrubTime: Double
    let scrubChanged: (Double) -> Void
    let scrubEditingChanged: (Bool) -> Void

    private var progressBinding: Binding<Double> {
        Binding(
            get: { displayedTime },
            set: { value in
                scrubTime = value
                scrubChanged(value)
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(VideoPlayerTimeFormatter.text(for: displayedTime))
                .frame(width: 46, alignment: .trailing)

            Slider(
                value: progressBinding,
                in: 0...max(duration, 1),
                onEditingChanged: scrubEditingChanged
            )
            .tint(.white)
            .accessibilityLabel(L.string("Playback Position"))

            Text(VideoPlayerTimeFormatter.text(for: duration))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 46, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.86))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private enum VideoPlayerTimeFormatter {
    static func text(for seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        }
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
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

    nonisolated var isVisualMedia: Bool {
        self == .image || self == .livePhoto || self == .video
    }

    nonisolated var isStillImageMedia: Bool {
        self == .image || self == .livePhoto
    }

    nonisolated var isCategorySelectionItem: Bool {
        switch self {
        case .image, .livePhoto, .video, .audio, .document, .archive, .other:
            true
        case .link:
            false
        }
    }

    var usesLongPressMediaPreview: Bool {
        self == .image || self == .livePhoto || self == .video
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
        case .album: AppTheme.primary
        case .audio: AppTheme.success
        case .documents: AppTheme.secondaryText
        case .links: AppTheme.warning
        }
    }
}

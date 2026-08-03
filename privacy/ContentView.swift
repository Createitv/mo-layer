import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var quickActions: QuickActionRouter
    @EnvironmentObject private var remoteChanges: CloudSyncRemoteChangeRouter
    @AppStorage("vault.hasSeenFirstRunGuide") private var hasSeenFirstRunGuide = false
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @State private var showQuickRecording = false
    @State private var showQuickRecordingMembership = false
    @State private var showCloudRestore = false
    @State private var didCheckCloudRestore = false
    @State private var hasRecoverableVaultData = false
    @State private var quickRecordingAlert: QuickRecordingAlert?
    @State private var cloudRestoreNotice: CloudRestoreNotice?
    @State private var sharedImportSession: ExternalSharedImportSession?
    @State private var sharedImportProgress: VaultImportProgress?
    @State private var sharedImportMessage: String?
    @State private var isSavingSharedImports = false
    @State private var showSharedImportMembership = false
    @State private var sharedImportResult: SharedImportResult?

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .english
    }

    var body: some View {
        Group {
            if !hasSeenFirstRunGuide && !auth.isConfigured {
                FirstRunGuideView {
                    hasSeenFirstRunGuide = true
                }
            } else if !auth.isConfigured {
                OnboardingView()
            } else {
                switch auth.sessionMode {
                case .cover:
                    if auth.requiresBiometricUnlock {
                        BiometricLockView()
                    } else if auth.requiresGestureUnlock {
                        LockView()
                    } else {
                        MainAppView()
                    }
                case .gestureGate:
                    if auth.requiresGestureUnlock {
                        LockView()
                    } else {
                        MainAppView()
                    }
                case .realVault:
                    MainAppView()
                case .decoyVault:
                    DecoyVaultView()
                }
            }
        }
        .environment(\.locale, selectedLanguage.locale)
        .task {
            startBackgroundLaunchRefresh()
        }
        .fullScreenCover(isPresented: $showQuickRecording) {
            AudioRecorderView(autoStart: true) { url, completion in
                saveQuickRecording(url, completion: completion)
            }
        }
        .fullScreenCover(isPresented: $showQuickRecordingMembership) {
            MembershipView(isRequiredBeforeUse: true)
                .environmentObject(subscription)
        }
        .sheet(isPresented: $showCloudRestore) {
            CloudVaultRestoreView {
                hasRecoverableVaultData = true
                refreshRecoverableVaultData()
            }
                .environmentObject(auth)
                .environmentObject(subscription)
                .environmentObject(sync)
                .environmentObject(vaultStore)
        }
        .fullScreenCover(item: $sharedImportSession) { session in
            SharedImportReviewSheet(
                imports: session.items,
                destination: session.destination,
                canImportAndSync: canImportVaultItems(count: session.items.count),
                isImporting: isSavingSharedImports,
                message: sharedImportMessage,
                saveAction: { selectedImports in
                    Task { await saveSharedImports(session, selectedImports: selectedImports) }
                },
                proAction: { showSharedImportMembership = true },
                cancelAction: { cancelSharedImports(session) }
            )
        }
        .fullScreenCover(isPresented: $showSharedImportMembership) {
            MembershipView(isRequiredBeforeUse: false)
                .environmentObject(subscription)
        }
        .fullScreenCover(item: $sharedImportResult) { result in
            SharedImportResultView(result: result) {
                sharedImportResult = nil
                auth.sessionMode = .cover
            }
        }
        .onAppear {
            handleQuickRecordingAction(quickActions.pendingAction)
            handleStoredQuickRecordingRequest()
        }
        .onChange(of: quickActions.pendingAction) { _, action in
            handleQuickRecordingAction(action)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            auth.refreshConfigurationFromSecureStorage()
            if auth.isConfigured {
                hasSeenFirstRunGuide = true
                hasRecoverableVaultData = true
            }
            vaultStore.setWriteAccess(subscription.canImportAndSync)
            _ = vaultStore.offloadOriginalsIfNeeded(context: modelContext)
            refreshRecoverableVaultData()
            handleStoredQuickRecordingRequest()
            Task {
                if remoteChanges.pendingReason != nil {
                    await handlePendingRemoteCloudChangeIfNeeded()
                } else {
                    await syncLatestCloudDataIfPossible(reason: nil)
                }
            }
        }
        .onChange(of: remoteChanges.pendingReason) { _, reason in
            guard let reason else { return }
            Task {
                await handleRemoteCloudChange(reason)
            }
        }
        .onChange(of: subscription.canImportAndSync) { _, canWrite in
            vaultStore.setWriteAccess(canWrite)
        }
        .onOpenURL { url in
            if isSharedImportsURL(url) {
                presentSharedImports(from: url)
                return
            }

            if url.isFileURL {
                presentSharedFileImport(from: url)
                return
            }

            guard isQuickRecordingURL(url) else { return }
            QuickRecordingRequestStore.requestQuickRecording()
            handleStoredQuickRecordingRequest()
        }
        .alert(item: $quickRecordingAlert) { alert in
            Alert(
                title: Text(L.string("Quick Recording")),
                message: Text(alert.message),
                dismissButton: .default(Text(L.string("OK")))
            )
        }
        .alert(item: $cloudRestoreNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(L.string("OK")))
            )
        }
    }

    private var canEnterExistingVault: Bool {
        auth.isConfigured || subscription.canEnterVault || hasRecoverableVaultData
    }

    @MainActor
    private func startBackgroundLaunchRefresh() {
        auth.refreshConfigurationFromSecureStorage()
        if auth.isConfigured {
            hasSeenFirstRunGuide = true
            hasRecoverableVaultData = true
        }
        refreshRecoverableVaultData()
        vaultStore.setWriteAccess(subscription.canImportAndSync)

        Task { @MainActor in
            await subscription.load()
            vaultStore.setWriteAccess(subscription.canImportAndSync)
            runBackgroundCloudSync()
        }

        Task { @MainActor in
            await sync.checkAccountStatus()
            await sync.ensureChangeSubscriptions()
        }

        Task { @MainActor in
            await restoreSecureConfigurationForLaunch()
            await checkForCloudRestore()
            refreshRecoverableVaultData()
        }
    }

    @MainActor
    private func restoreSecureConfigurationForLaunch() async {
        // 删除 App 后 UserDefaults/SwiftData 会清空；先等 iCloud Keychain 尝试恢复密钥和手势，避免误进 setup。
        for attempt in 0..<8 {
            auth.refreshConfigurationFromSecureStorage()
            if auth.isConfigured {
                hasSeenFirstRunGuide = true
                hasRecoverableVaultData = true
                return
            }
            guard attempt < 7 else { break }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    @MainActor
    private func checkForCloudRestore() async {
        guard !didCheckCloudRestore else { return }
        didCheckCloudRestore = true
        auth.refreshConfigurationFromSecureStorage()
        refreshRecoverableVaultData()
        guard !auth.isConfigured else {
            hasSeenFirstRunGuide = true
            hasRecoverableVaultData = true
            return
        }
        await sync.checkAccountStatus()
        let result = await vaultStore.checkForRemoteVaultRestore(context: modelContext, sync: sync)
        switch result {
        case .noRemoteVault:
            break
        case .needsRecoveryKey:
            showCloudRestore = true
        case .restoredAutomatically(let summary):
            auth.refreshConfigurationFromSecureStorage()
            hasRecoverableVaultData = true
            cloudRestoreNotice = CloudRestoreNotice(
                title: L.string("iCloud Vault Restored"),
                message: summary.displayText
            )
        case .failed(let message):
            cloudRestoreNotice = CloudRestoreNotice(
                title: L.string("iCloud Restore Failed"),
                message: message
            )
        }
        refreshRecoverableVaultData()
    }

    @MainActor
    private func refreshRecoverableVaultData() {
        if auth.isConfigured && VaultCryptoService.hasRecoverableRootKey() {
            hasRecoverableVaultData = true
            return
        }
        hasRecoverableVaultData = hasRecoverableVaultData || vaultStore.hasLocalVaultData(context: modelContext)
    }

    @MainActor
    private func handleRemoteCloudChange(_ reason: CloudRemoteChangeReason) async {
        sync.appendLog("Remote CloudKit change received recordType=\(reason.displayName)")
        auth.refreshConfigurationFromSecureStorage()
        guard auth.isConfigured, VaultCryptoService.hasRootKey() else {
            sync.appendLog("Remote CloudKit change deferred: vault root key is not available yet")
            return
        }
        await syncLatestCloudDataIfPossible(reason: reason)
        if subscription.canPullFromCloud {
            remoteChanges.consume(reason)
        }
    }

    @MainActor
    private func handlePendingRemoteCloudChangeIfNeeded() async {
        guard let reason = remoteChanges.pendingReason else { return }
        await handleRemoteCloudChange(reason)
    }

    private func runBackgroundCloudSync() {
        Task { @MainActor in
            if remoteChanges.pendingReason != nil {
                await handlePendingRemoteCloudChangeIfNeeded()
            } else {
                await syncLatestCloudDataIfPossible(reason: nil)
            }
        }
    }

    @MainActor
    private func syncLatestCloudDataIfPossible(reason: CloudRemoteChangeReason?) async {
        auth.refreshConfigurationFromSecureStorage()
        guard auth.isConfigured, VaultCryptoService.hasRootKey(), subscription.canPullFromCloud else { return }
        vaultStore.setWriteAccess(subscription.canImportAndSync)
        if let reason {
            sync.appendLog("Syncing latest iCloud data reason=\(reason.displayName)")
        } else {
            sync.appendLog("Syncing latest iCloud data")
        }
        await vaultStore.syncCloudToLocal(
            context: modelContext,
            sync: sync,
            allowsCloudSync: subscription.canPullFromCloud,
            allowsCloudWrite: subscription.canImportAndSync
        )
        refreshRecoverableVaultData()
    }

    private func handleQuickRecordingAction(_ action: QuickAction?) {
        guard action == .recorder else { return }
        quickActions.consume(.recorder)
        QuickRecordingRequestStore.requestQuickRecording()
        handleStoredQuickRecordingRequest()
    }

    private func isQuickRecordingURL(_ url: URL) -> Bool {
        isAppURL(url) && url.host() == "quick-recording"
    }

    private func isSharedImportsURL(_ url: URL) -> Bool {
        isAppURL(url) && url.host() == "shared-imports"
    }

    private func isAppURL(_ url: URL) -> Bool {
        url.scheme == "privacy" || url.scheme == "molayer"
    }

    @MainActor
    private func presentSharedImports(from url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let batchId = components?
            .queryItems?
            .first(where: { $0.name == "batch" })?
            .value
        let urlDestination = SharedImportDestination.from(
            components?
                .queryItems?
                .first(where: { $0.name == "destination" })?
                .value
        )
        let imports = ImportService.pendingSharedImports(batchId: batchId)
        guard !imports.isEmpty else {
            sharedImportMessage = L.string("No shared files were found.")
            return
        }

        let destination = imports.first?.destination ?? urlDestination
        sharedImportProgress = nil
        sharedImportMessage = L.format("%d file(s) ready to save.", imports.count)
        sharedImportSession = ExternalSharedImportSession(
            id: batchId ?? UUID().uuidString,
            items: imports,
            destination: destination
        )
    }

    @MainActor
    private func presentSharedFileImport(from url: URL) {
        let batchId = UUID().uuidString
        guard let item = ImportService.stageFileForReview(url: url, batchId: batchId) else {
            sharedImportMessage = L.string("This file could not be opened.")
            return
        }

        sharedImportProgress = nil
        sharedImportMessage = L.string("1 file ready to save.")
        sharedImportSession = ExternalSharedImportSession(id: batchId, items: [item], destination: item.destination)
    }

    private func handleStoredQuickRecordingRequest() {
        guard QuickRecordingRequestStore.consumeQuickRecordingRequest() else { return }
        Task { await startQuickRecordingIfAllowed() }
    }

    @MainActor
    private func saveSharedImports(
        _ session: ExternalSharedImportSession,
        selectedImports: [ImportService.PendingSharedImport]
    ) async {
        guard !isSavingSharedImports else { return }
        guard !selectedImports.isEmpty else { return }
        isSavingSharedImports = true
        defer { isSavingSharedImports = false }

        await subscription.load()
        auth.refreshConfigurationFromSecureStorage()
        _ = try? VaultCryptoService.restoreRootKeyFromICloudKeychain()

        guard hasSeenFirstRunGuide, auth.isConfigured, VaultCryptoService.hasRootKey() else {
            sharedImportMessage = L.string("Set up your private vault before saving shared files.")
            return
        }

        guard canImportVaultItems(count: selectedImports.count) else {
            sharedImportMessage = freeImportLimitMessage()
            return
        }

        vaultStore.setWriteAccess(true)
        let selectedIds = Set(selectedImports.map(\.id))
        let skippedImports = session.items.filter { !selectedIds.contains($0.id) }
        ImportService.discardSharedImports(skippedImports)

        sharedImportProgress = VaultImportProgress(totalCount: selectedImports.count)
        sharedImportMessage = L.format("Saving %d file(s)...", selectedImports.count)

        let summary = await ImportService.importPendingSharedImports(
            selectedImports,
            context: modelContext,
            vaultStore: vaultStore,
            sync: sync,
            folderId: session.destination.folderId,
            syncAfterImport: false,
            progress: { event in
                recordSharedImportProgress(event)
            }
        )

        if var progress = sharedImportProgress {
            progress.finish()
            sharedImportProgress = progress
        }

        if summary.importedCount > 0, subscription.canImportAndSync {
            sharedImportMessage = L.format("Saved %d file(s). iCloud backup will continue automatically.", summary.importedCount)
            Task { @MainActor in
                await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
            }
        } else if summary.importedCount > 0 {
            sharedImportMessage = L.format("Saved %d file(s).", summary.importedCount)
        } else if summary.skippedDuplicateCount > 0, summary.failedCount == 0 {
            sharedImportMessage = summary.displayMessage
        }

        if summary.failedCount == 0, summary.importedCount > 0 {
            if sharedImportSession?.id == session.id {
                let result = SharedImportResult(
                    importedCount: summary.importedCount,
                    destination: session.destination,
                    items: selectedImports
                )
                sharedImportSession = nil
                sharedImportProgress = nil
                sharedImportMessage = nil
                Task { @MainActor in
                    sharedImportResult = result
                }
            }
        } else if summary.failedCount == 0, summary.skippedDuplicateCount > 0 {
            if sharedImportSession?.id == session.id {
                sharedImportSession = nil
                sharedImportProgress = nil
            }
        } else if summary.failedCount > 0 {
            let remainingImports = ImportService.pendingSharedImports()
                .filter { selectedIds.contains($0.id) }
            if sharedImportSession?.id == session.id {
                sharedImportSession = ExternalSharedImportSession(
                    id: session.id,
                    items: remainingImports,
                    destination: session.destination
                )
            }
            sharedImportMessage = L.string("These shared files could not be saved. You can retry or cancel.")
        } else {
            sharedImportMessage = L.string("These shared files could not be saved. You can retry or cancel.")
        }
    }

    @MainActor
    private func recordSharedImportProgress(_ event: VaultImportProgressEvent) {
        guard var progress = sharedImportProgress else { return }
        switch event {
        case .currentItem(let item):
            progress.updateCurrentItem(item)
        case .completed(let result):
            progress.record(result)
        }
        sharedImportProgress = progress
        sharedImportMessage = progress.statusText
    }

    @MainActor
    private func cancelSharedImports(_ session: ExternalSharedImportSession) {
        guard !isSavingSharedImports else { return }
        ImportService.discardSharedImports(session.items)
        if sharedImportSession?.id == session.id {
            sharedImportSession = nil
            sharedImportProgress = nil
            sharedImportMessage = nil
        }
    }

    @MainActor
    private func startQuickRecordingIfAllowed() async {
        await subscription.load()
        vaultStore.setWriteAccess(canImportVaultItems(count: 1))

        guard hasSeenFirstRunGuide, auth.isConfigured, VaultCryptoService.hasRootKey() else {
            quickRecordingAlert = QuickRecordingAlert(
                message: L.string("Set up your private vault before using quick recording.")
            )
            return
        }

        guard canImportVaultItems(count: 1) else {
            showQuickRecordingMembership = true
            return
        }

        showQuickRecording = true
    }

    private func saveQuickRecording(_ url: URL, completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            guard canImportVaultItems(count: 1), auth.isConfigured, VaultCryptoService.hasRootKey() else {
                try? FileManager.default.removeItem(at: url)
                completion(false)
                return
            }
            vaultStore.setWriteAccess(true)

            let summary = await ImportService.importFiles(
                urls: [url],
                context: modelContext,
                vaultStore: vaultStore,
                sync: sync,
                source: "Quick Recording",
                syncAfterImport: subscription.canImportAndSync
            )
            try? FileManager.default.removeItem(at: url)
            if subscription.canImportAndSync {
                await vaultStore.syncPendingChanges(context: modelContext, sync: sync)
            }
            let success = summary.importedCount > 0
            completion(success)

            if !success {
                quickRecordingAlert = QuickRecordingAlert(
                    message: summary.skippedDuplicateCount > 0 ? summary.displayMessage : L.string("The recording could not be saved.")
                )
            }
        }
    }

    @MainActor
    private func canImportVaultItems(count incomingCount: Int) -> Bool {
        let descriptor = FetchDescriptor<VaultItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
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

private struct QuickRecordingAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct ExternalSharedImportSession: Identifiable {
    let id: String
    let items: [ImportService.PendingSharedImport]
    let destination: SharedImportDestination
}

private struct SharedImportResult: Identifiable {
    let id = UUID()
    let importedCount: Int
    let destination: SharedImportDestination
    let items: [ImportService.PendingSharedImport]
}

private struct CloudRestoreNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct SharedImportResultView: View {
    let result: SharedImportResult
    let openAppAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.success)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.format("Saved %d file(s).", result.importedCount))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(L.format("Saved to %@", result.destination.title))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Text(L.string("This import was encrypted locally. iCloud backup will continue in the background when available."))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Section {
                        ForEach(result.items.prefix(result.importedCount)) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.primary)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.originalName)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                        .foregroundStyle(AppTheme.ink)
                                    Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(L.string("Shared Files"))
                    } footer: {
                        Text(L.string("Only this import is shown here. Enter Mo Layer to unlock and view the full vault."))
                    }
                }

                Button(action: openAppAction) {
                    Label(L.string("Open Mo Layer"), systemImage: "lock.open")
                }
                .buttonStyle(AppButtonStyle())
                .padding()
                .background(AppTheme.background)
            }
            .navigationTitle(L.string("Shared Import Saved"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FirstRunGuideView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                        Text(L.string("Welcome to Palimpsest"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(L.string("It looks like a simple notes app. Your encrypted private vault opens only with the correct gesture."))
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    VStack(spacing: 12) {
                        GuideStep(icon: "note.text", title: L.string("Disguised notes app"), detail: L.string("Daily launches show ordinary notes, todos, and conversations instead of exposing your real vault."))
                        GuideStep(icon: "scribble.variable", title: L.string("Gesture entry"), detail: L.string("Use your own freeform gesture to enter the vault. Reset it with your security code if you forget it."))
                        GuideStep(icon: "square.and.arrow.down", title: L.string("Encrypt on import"), detail: L.string("Photos, videos, and files are encrypted on this device before optional iCloud sync."))
                        GuideStep(icon: "theatermasks", title: L.string("Decoy notes"), detail: L.string("Wrong gestures or access codes open a realistic notes space, so real content stays hidden."))
                    }

                    Button(L.string("Set Up Palimpsest"), action: onStart)
                        .buttonStyle(AppButtonStyle())
                }
                .padding(28)
            }
        }
    }
}

private struct GuideStep: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 38, height: 38)
                .background(AppTheme.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(14)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(CloudKitSyncService())
        .environmentObject(VaultStore())
        .environmentObject(VaultImportQueue())
        .environmentObject(SubscriptionManager())
        .environmentObject(QuickActionRouter.shared)
        .environmentObject(CloudSyncRemoteChangeRouter.shared)
}

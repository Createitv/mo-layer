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
    @State private var isCheckingVaultAccess = true
    @State private var hasRecoverableVaultData = false
    @State private var quickRecordingAlert: QuickRecordingAlert?
    @State private var cloudRestoreNotice: CloudRestoreNotice?

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .english
    }

    var body: some View {
        Group {
            if isCheckingVaultAccess {
                VaultAccessCheckingView()
            } else if !hasSeenFirstRunGuide {
                FirstRunGuideView {
                    hasSeenFirstRunGuide = true
                }
            } else if !auth.isConfigured && canEnterExistingVault {
                OnboardingView()
            } else if !auth.isConfigured {
                MembershipView(isRequiredBeforeUse: true)
            } else if !canEnterExistingVault {
                MembershipView(isRequiredBeforeUse: true)
            } else {
                switch auth.sessionMode {
                case .cover:
                    if auth.requiresBiometricUnlock {
                        BiometricLockView()
                    } else {
                        LockView()
                    }
                case .gestureGate:
                    LockView()
                case .realVault:
                    MainAppView()
                case .decoyVault:
                    DecoyVaultView()
                }
            }
        }
        .environment(\.locale, selectedLanguage.locale)
        .task {
            isCheckingVaultAccess = true
            await restoreSecureConfigurationForLaunch()
            await subscription.load()
            vaultStore.setWriteAccess(subscription.canImportAndSync)
            await sync.checkAccountStatus()
            await sync.ensureChangeSubscriptions()
            await checkForCloudRestore()
            refreshRecoverableVaultData()
            isCheckingVaultAccess = false
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
            refreshRecoverableVaultData()
            handleStoredQuickRecordingRequest()
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
        subscription.canEnterVault || hasRecoverableVaultData
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
        isCheckingVaultAccess = true
        auth.refreshConfigurationFromSecureStorage()
        refreshRecoverableVaultData()
        guard !auth.isConfigured else {
            hasSeenFirstRunGuide = true
            hasRecoverableVaultData = true
            isCheckingVaultAccess = false
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
        isCheckingVaultAccess = false
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
            remoteChanges.consume(reason)
            return
        }
        vaultStore.setWriteAccess(subscription.canImportAndSync)
        await vaultStore.syncCloudToLocal(
            context: modelContext,
            sync: sync,
            allowsCloudSync: subscription.canImportAndSync
        )
        refreshRecoverableVaultData()
        remoteChanges.consume(reason)
    }

    private func handleQuickRecordingAction(_ action: QuickAction?) {
        guard action == .recorder else { return }
        quickActions.consume(.recorder)
        QuickRecordingRequestStore.requestQuickRecording()
        handleStoredQuickRecordingRequest()
    }

    private func isQuickRecordingURL(_ url: URL) -> Bool {
        url.scheme == "privacy" && url.host() == "quick-recording"
    }

    private func handleStoredQuickRecordingRequest() {
        guard QuickRecordingRequestStore.consumeQuickRecordingRequest() else { return }
        Task { await startQuickRecordingIfAllowed() }
    }

    @MainActor
    private func startQuickRecordingIfAllowed() async {
        await subscription.load()
        vaultStore.setWriteAccess(subscription.canImportAndSync)

        guard hasSeenFirstRunGuide, auth.isConfigured, VaultCryptoService.hasRootKey() else {
            quickRecordingAlert = QuickRecordingAlert(
                message: L.string("Set up your private vault before using quick recording.")
            )
            return
        }

        guard subscription.canImportAndSync else {
            showQuickRecordingMembership = true
            return
        }

        showQuickRecording = true
    }

    private func saveQuickRecording(_ url: URL, completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            guard subscription.canImportAndSync, auth.isConfigured, VaultCryptoService.hasRootKey() else {
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
                source: "Quick Recording"
            )
            try? FileManager.default.removeItem(at: url)
            let success = summary.importedCount > 0
            completion(success)

            if !success {
                quickRecordingAlert = QuickRecordingAlert(
                    message: L.string("The recording could not be saved.")
                )
            }
        }
    }
}

private struct QuickRecordingAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct CloudRestoreNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct VaultAccessCheckingView: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ProgressView(L.string("Checking for existing iCloud vault..."))
                .foregroundStyle(AppTheme.secondaryText)
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

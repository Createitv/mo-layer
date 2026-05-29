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
    @AppStorage("vault.hasSeenFirstRunGuide") private var hasSeenFirstRunGuide = false
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var showQuickRecording = false
    @State private var showQuickRecordingMembership = false
    @State private var quickRecordingAlert: QuickRecordingAlert?

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .english
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }

    var body: some View {
        Group {
            if !hasSeenFirstRunGuide {
                FirstRunGuideView {
                    hasSeenFirstRunGuide = true
                }
            } else if !auth.isConfigured && !subscription.canEnterVault {
                MembershipView(isRequiredBeforeUse: true)
            } else if !auth.isConfigured {
                OnboardingView()
            } else if !subscription.canEnterVault {
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
        .preferredColorScheme(selectedAppearance.colorScheme)
        .environment(\.locale, selectedLanguage.locale)
        .task {
            await subscription.load()
        }
        .fullScreenCover(isPresented: $showQuickRecording) {
            AudioRecorderView(autoStart: true) { url, completion in
                saveQuickRecording(url, completion: completion)
            }
        }
        .fullScreenCover(isPresented: $showQuickRecordingMembership) {
            MembershipView(isRequiredBeforeUse: true)
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
            handleStoredQuickRecordingRequest()
        }
        .onOpenURL { url in
            guard url.scheme == "privacy", url.host() == "quick-recording" else { return }
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
    }

    private func handleQuickRecordingAction(_ action: QuickAction?) {
        guard action == .recorder else { return }
        quickActions.consume(.recorder)
        QuickRecordingRequestStore.requestQuickRecording()
        handleStoredQuickRecordingRequest()
    }

    private func handleStoredQuickRecordingRequest() {
        guard QuickRecordingRequestStore.consumeQuickRecordingRequest() else { return }
        Task { await startQuickRecordingIfAllowed() }
    }

    @MainActor
    private func startQuickRecordingIfAllowed() async {
        await subscription.load()

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
                        Text("Welcome to Palimpsest")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("It looks like a simple notes app. Your encrypted private vault opens only with the correct gesture.")
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    VStack(spacing: 12) {
                        GuideStep(icon: "note.text", title: "Disguised notes app", detail: "Daily launches show ordinary notes, todos, and conversations instead of exposing your real vault.")
                        GuideStep(icon: "scribble.variable", title: "Gesture entry", detail: "Use your own freeform gesture to enter the vault. Reset it with your security code if you forget it.")
                        GuideStep(icon: "square.and.arrow.down", title: "Encrypt on import", detail: "Photos, videos, and files are encrypted on this device before optional iCloud sync.")
                        GuideStep(icon: "theatermasks", title: "Decoy notes", detail: "Wrong gestures or access codes open a realistic notes space, so real content stays hidden.")
                    }

                    Button("Set Up Palimpsest", action: onStart)
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
        .environmentObject(SubscriptionManager())
        .environmentObject(QuickActionRouter.shared)
}

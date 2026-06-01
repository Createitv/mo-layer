import SwiftData
import SwiftUI
import UIKit

enum AppRootPresentation {
    static let rebuildsRootWhenSettingsChange = false
    static let requiresActiveMembershipBeforeVaultAccess = true
}

@main
struct privacyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthenticationManager()
    @StateObject private var sync = CloudKitSyncService()
    @StateObject private var vaultStore = VaultStore()
    @StateObject private var importQueue = VaultImportQueue()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var quickActions = QuickActionRouter.shared
    @StateObject private var remoteChanges = CloudSyncRemoteChangeRouter.shared

    init() {
        AppLanguage.installDefaultLanguagePreference()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VaultItem.self,
            VaultFolder.self,
            VaultTag.self,
            DecoyNoteRecord.self,
            SecurityEvent.self,
            SubscriptionState.self,
            VaultManifest.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppPreferencesRootView {
                ContentView()
                    .environmentObject(auth)
                    .environmentObject(sync)
                    .environmentObject(vaultStore)
                    .environmentObject(importQueue)
                    .environmentObject(subscription)
                    .environmentObject(quickActions)
                    .environmentObject(remoteChanges)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

private struct AppPreferencesRootView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .english
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }

    var body: some View {
        content
            .environment(\.locale, selectedLanguage.locale)
            .preferredColorScheme(selectedAppearance.colorScheme)
            .onAppear {
                applyWindowAppearance()
            }
            .onChange(of: appearance) { _, _ in
                applyWindowAppearance()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                applyWindowAppearance()
            }
    }

    private func applyWindowAppearance() {
        let selectedAppearance = selectedAppearance
        Task { @MainActor in
            selectedAppearance.applyToConnectedWindows()
        }
    }
}

@MainActor
extension AppAppearance {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func applyToConnectedWindows() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = userInterfaceStyle }
    }
}

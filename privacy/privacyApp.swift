import SwiftData
import SwiftUI

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
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var quickActions = QuickActionRouter.shared
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue

    init() {
        AppLanguage.installDefaultLanguagePreference()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VaultItem.self,
            VaultFolder.self,
            VaultTag.self,
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
            ContentView()
                .environmentObject(auth)
                .environmentObject(sync)
                .environmentObject(vaultStore)
                .environmentObject(subscription)
                .environmentObject(quickActions)
                .environment(\.locale, AppLanguage(rawValue: language)?.locale ?? Locale(identifier: "en"))
        }
        .modelContainer(sharedModelContainer)
    }
}

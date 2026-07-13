import Combine
import SwiftData
import SwiftUI
import UIKit

enum AppRootPresentation {
    static let rebuildsRootWhenSettingsChange = false
    static let requiresActiveMembershipBeforeVaultAccess = true
    static let blocksLaunchForCloudRefresh = false
}

enum AppModelStore {
    static let appGroupIdentifier = "group.app.landlady.www.privacy"
    static let storeFileName = "default.store"
    static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    static var schema: Schema {
        Schema([
            VaultItem.self,
            VaultFolder.self,
            VaultTag.self,
            DecoyNoteRecord.self,
            SecurityEvent.self,
            SubscriptionState.self,
            VaultManifest.self
        ])
    }

    static var isProtectedDataAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIApplication.shared.isProtectedDataAvailable
        #endif
    }

    static var storeURL: URL {
        applicationSupportDirectory.appendingPathComponent(storeFileName)
    }

    static var storeSidecarURLs: [URL] {
        storeSidecarFileNames.map { applicationSupportDirectory.appendingPathComponent($0) }
    }

    static var storeSidecarFileNames: [String] {
        [
            "\(storeFileName)-wal",
            "\(storeFileName)-shm"
        ]
    }

    static func makeContainer(protectedDataAvailable: Bool = isProtectedDataAvailable) throws -> AppModelContainer {
        let schema = schema
        guard protectedDataAvailable else {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return AppModelContainer(
                container: try ModelContainer(for: schema, configurations: [configuration]),
                usesPersistentStore: false
            )
        }

        let configuration = try makePersistentConfiguration(schema: schema)
        return AppModelContainer(
            container: try ModelContainer(for: schema, configurations: [configuration]),
            usesPersistentStore: true
        )
    }

    static func makePersistentConfiguration(schema: Schema) throws -> ModelConfiguration {
        try prepareStoreLocation()
        return ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    }

    static func prepareStoreLocation() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try applyStoreFileProtection(at: applicationSupportDirectory)

        for url in [storeURL] + storeSidecarURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try applyStoreFileProtection(at: url)
        }
    }

    private static var applicationSupportDirectory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func applyStoreFileProtection(at url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: fileProtection], ofItemAtPath: url.path)
    }
}

struct AppModelContainer {
    let container: ModelContainer
    let usesPersistentStore: Bool
}

@MainActor
final class AppModelContainerController: ObservableObject {
    @Published private(set) var modelContainer: AppModelContainer

    init() {
        do {
            modelContainer = try AppModelStore.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var container: ModelContainer {
        modelContainer.container
    }

    var usesPersistentStore: Bool {
        modelContainer.usesPersistentStore
    }

    func usePersistentStoreWhenProtectedDataIsAvailable() {
        guard !usesPersistentStore, AppModelStore.isProtectedDataAvailable else { return }
        do {
            let schema = AppModelStore.schema
            let configuration = try AppModelStore.makePersistentConfiguration(schema: schema)
            modelContainer = AppModelContainer(
                container: try ModelContainer(for: schema, configurations: [configuration]),
                usesPersistentStore: true
            )
        } catch {
            assertionFailure("Could not switch to persistent ModelContainer: \(error)")
        }
    }
}

@main
struct privacyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var modelContainerController = AppModelContainerController()
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

    var body: some Scene {
        WindowGroup {
            AppPreferencesRootView {
                ContentView()
                    .id(modelContainerController.usesPersistentStore)
                    .environmentObject(auth)
                    .environmentObject(sync)
                    .environmentObject(vaultStore)
                    .environmentObject(importQueue)
                    .environmentObject(subscription)
                    .environmentObject(quickActions)
                    .environmentObject(remoteChanges)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                modelContainerController.usePersistentStoreWhenProtectedDataIsAvailable()
            }
        }
        .modelContainer(modelContainerController.container)
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
        #if targetEnvironment(macCatalyst)
        return
        #else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = userInterfaceStyle }
        #endif
    }
}

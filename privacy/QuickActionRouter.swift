import Combine
import SwiftUI
import UIKit

enum QuickAction: String {
    case importHub = "app.landlady.www.privacy.quick-import"
    case camera = "app.landlady.www.privacy.quick-camera"
    case recorder = "app.landlady.www.privacy.quick-recorder"
}

@MainActor
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()

    @Published var pendingAction: QuickAction?
    @Published var pendingCategory: VaultCategory?

    private init() {}

    func handleShortcut(type: String) {
        pendingAction = QuickAction(rawValue: type)
    }

    func consume(_ action: QuickAction) {
        if pendingAction == action {
            pendingAction = nil
        }
    }

    func route(to category: VaultCategory) {
        pendingCategory = category
    }

    func consume(_ category: VaultCategory) {
        if pendingCategory == category {
            pendingCategory = nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            Task { @MainActor in
                QuickActionRouter.shared.handleShortcut(type: shortcut.type)
            }
            return false
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            QuickActionRouter.shared.handleShortcut(type: shortcutItem.type)
            completionHandler(QuickAction(rawValue: shortcutItem.type) != nil)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            CloudSyncRemoteChangeRouter.shared.markRemoteNotificationsRegistered()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            CloudSyncRemoteChangeRouter.shared.markRemoteNotificationsFailed(error.localizedDescription)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let handled = CloudSyncRemoteChangeRouter.shared.receive(userInfo: userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }
}

#if targetEnvironment(macCatalyst)
@MainActor
struct MoLayerCommands: Commands {
    var body: some Commands {
        CommandMenu(L.string("Mo Layer")) {
            if PlatformCapabilities.routes.shortcutEntry == .commands {
                Button(L.string("Import")) {
                    QuickActionRouter.shared.handleShortcut(type: QuickAction.importHub.rawValue)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button(L.string("Record Audio")) {
                    QuickActionRouter.shared.handleShortcut(type: QuickAction.recorder.rawValue)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
#endif

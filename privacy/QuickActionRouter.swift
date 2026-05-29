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
}

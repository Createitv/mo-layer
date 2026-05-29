import Combine
import Foundation
@preconcurrency import RevenueCat

enum SubscriptionLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum MembershipAccessLevel: Equatable {
    case activePro
    case expiredReadOnly
    case lockedUntilPro

    var allowsVaultEntry: Bool {
        switch self {
        case .activePro, .expiredReadOnly:
            true
        case .lockedUntilPro:
            false
        }
    }

    var allowsImportAndCloudSync: Bool {
        self == .activePro
    }
}

@MainActor
final class SubscriptionManager: NSObject, ObservableObject {
    nonisolated static let monthly = "privacy.vault.pro.monthly"
    nonisolated static let yearly = "privacy.vault.pro.yearly"
    nonisolated static let lifetime = "privacy.vault.pro.lifetime"
    nonisolated static let expectedProductIDs = [monthly, yearly, lifetime]
    nonisolated static let revenueCatEntitlementID = "pro"
    nonisolated static let revenueCatAPIKeyInfoPlistKey = "REVENUECAT_API_KEY"
    nonisolated static var grantsDeveloperAccessInDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    private nonisolated static let revenueCatPlaceholderAPIKey = "REPLACE_WITH_REVENUECAT_PUBLIC_IOS_KEY"
    private nonisolated static let hasActivatedProStorageKey = "subscription.hasActivatedPro"

    @Published var packages: [Package] = []
    @Published var missingProductIDs: [String] = []
    @Published var loadState: SubscriptionLoadState = .idle
    @Published var isPro = false
    @Published var statusText = L.string("Free Plan")
    @Published private(set) var hasActivatedPro = UserDefaults.standard.bool(forKey: hasActivatedProStorageKey)
    private var isRevenueCatReady = false

    override init() {
        super.init()
        configureRevenueCat(apiKey: Bundle.main.object(forInfoDictionaryKey: Self.revenueCatAPIKeyInfoPlistKey) as? String)
        applyDeveloperAccessIfNeeded()
    }

    nonisolated static func missingProductIDs(from loadedIDs: [String]) -> [String] {
        expectedProductIDs.filter { !loadedIDs.contains($0) }
    }

    nonisolated static func isRevenueCatAPIKeyConfigured(_ apiKey: String?) -> Bool {
        guard let apiKey else { return false }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != revenueCatPlaceholderAPIKey
    }

    nonisolated static func displayOrder(forStoreProductID productID: String) -> Int {
        expectedProductIDs.firstIndex(of: productID) ?? Int.max
    }

    nonisolated static func accessLevel(isPro: Bool, hasActivatedPro: Bool) -> MembershipAccessLevel {
        if isPro { return .activePro }
        if hasActivatedPro { return .expiredReadOnly }
        return .lockedUntilPro
    }

    var accessLevel: MembershipAccessLevel {
        Self.accessLevel(isPro: isPro, hasActivatedPro: hasActivatedPro)
    }

    var canEnterVault: Bool {
        accessLevel.allowsVaultEntry
    }

    var canImportAndSync: Bool {
        accessLevel.allowsImportAndCloudSync
    }

    func configureRevenueCat(apiKey: String?) {
        guard Self.isRevenueCatAPIKeyConfigured(apiKey) else {
            isRevenueCatReady = false
            return
        }
        if !Purchases.isConfigured {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: apiKey!.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        Purchases.shared.delegate = self
        isRevenueCatReady = true
    }

    func load() async {
        if loadState == .loading { return }
        applyDeveloperAccessIfNeeded()
        guard isRevenueCatReady else {
            packages = []
            missingProductIDs = Self.expectedProductIDs
            loadState = .failed(L.string("RevenueCat API key is not configured."))
            statusText = L.string("RevenueCat API key is not configured.")
            applyDeveloperAccessIfNeeded()
            return
        }
        loadState = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            let fetchedPackages = offerings.current?.availablePackages ?? []
            packages = fetchedPackages.sorted { lhs, rhs in
                Self.displayOrder(forStoreProductID: lhs.storeProduct.productIdentifier) < Self.displayOrder(forStoreProductID: rhs.storeProduct.productIdentifier)
            }
            missingProductIDs = Self.missingProductIDs(from: packages.map(\.storeProduct.productIdentifier))
            loadState = .loaded
            await refreshEntitlements()
        } catch {
            packages = []
            missingProductIDs = Self.expectedProductIDs
            loadState = .failed(L.string("Unable to load membership products"))
            statusText = L.string("Unable to load membership products")
            applyDeveloperAccessIfNeeded()
        }
    }

    func purchase(_ package: Package) async {
        guard isRevenueCatReady else {
            statusText = L.string("RevenueCat API key is not configured.")
            return
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            applyCustomerInfo(result.customerInfo)
            applyDeveloperAccessIfNeeded()
        } catch {
            statusText = L.string("Purchase Failed")
            applyDeveloperAccessIfNeeded()
        }
    }

    func restorePurchases() async {
        guard isRevenueCatReady else {
            statusText = L.string("RevenueCat API key is not configured.")
            return
        }
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(customerInfo)
            applyDeveloperAccessIfNeeded()
        } catch {
            statusText = L.string("Restore Failed")
            applyDeveloperAccessIfNeeded()
        }
    }

    func refreshEntitlements() async {
        guard isRevenueCatReady else {
            isPro = false
            statusText = L.string("Free Plan")
            applyDeveloperAccessIfNeeded()
            return
        }
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            applyCustomerInfo(customerInfo)
            applyDeveloperAccessIfNeeded()
        } catch {
            statusText = L.string("Unable to load membership products")
            applyDeveloperAccessIfNeeded()
        }
    }

    private func applyCustomerInfo(_ customerInfo: CustomerInfo) {
        let active = customerInfo.entitlements[Self.revenueCatEntitlementID]?.isActive == true
        isPro = active
        if active {
            markProActivated()
        }
        statusText = active ? L.string("Pro Active") : L.string("Free Plan")
    }

    @discardableResult
    private func applyDeveloperAccessIfNeeded() -> Bool {
        guard Self.grantsDeveloperAccessInDebug else { return false }
        isPro = true
        statusText = L.string("Developer Access")
        return true
    }

    private func markProActivated() {
        guard !hasActivatedPro else { return }
        hasActivatedPro = true
        UserDefaults.standard.set(true, forKey: Self.hasActivatedProStorageKey)
    }
}

extension SubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.applyCustomerInfo(customerInfo)
        }
    }
}

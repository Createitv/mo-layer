import Combine
import Foundation
@preconcurrency import RevenueCat

enum SubscriptionLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum MoLayerEntryAction: Equatable {
    case enter
    case explainPro
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

    var moLayerEntryAction: MoLayerEntryAction {
        allowsVaultEntry ? .enter : .explainPro
    }

    var allowsImportAndCloudSync: Bool {
        self == .activePro
    }

    var allowsCloudPull: Bool {
        switch self {
        case .activePro, .expiredReadOnly:
            true
        case .lockedUntilPro:
            false
        }
    }
}

struct RestorePurchaseFeedback: Equatable {
    enum Kind: Equatable {
        case success
        case warning
    }

    let kind: Kind
    let message: String

    static func restored(hasActivePro: Bool) -> RestorePurchaseFeedback {
        if hasActivePro {
            return RestorePurchaseFeedback(kind: .success, message: L.string("Purchases restored. Pro is active."))
        }
        return RestorePurchaseFeedback(kind: .warning, message: L.string("No previous purchases found for this Apple ID."))
    }

    static func failed() -> RestorePurchaseFeedback {
        RestorePurchaseFeedback(kind: .warning, message: L.string("Restore purchase failed. Please try again."))
    }

    static func codeRedemptionUnavailable() -> RestorePurchaseFeedback {
        RestorePurchaseFeedback(kind: .warning, message: L.string("Code redemption is unavailable. Please try again later."))
    }

    static func codeRedemptionOpened(hasActivePro: Bool) -> RestorePurchaseFeedback {
        if hasActivePro {
            return RestorePurchaseFeedback(kind: .success, message: L.string("Code redeemed. Pro is active."))
        }
        return RestorePurchaseFeedback(kind: .warning, message: L.string("Code redemption opened. Complete the App Store prompt, then Pro will refresh automatically."))
    }
}

enum VaultFreeImportPolicy {
    static let freeItemLimit = 99

    static func countsTowardFreeLimit(_ kind: VaultItemKind) -> Bool {
        switch kind {
        case .image, .livePhoto, .video, .audio, .document, .archive, .other:
            true
        case .link:
            false
        }
    }

    static func countedItemCount(in items: [VaultItem]) -> Int {
        items.filter { item in
            item.deletedAt == nil && countsTowardFreeLimit(item.kind)
        }.count
    }

    static func remainingFreeSlots(currentCount: Int, isPro: Bool) -> Int? {
        guard !isPro else { return nil }
        return max(freeItemLimit - currentCount, 0)
    }

    static func canImport(currentCount: Int, incomingCount: Int, isPro: Bool) -> Bool {
        guard incomingCount > 0 else { return true }
        guard !isPro else { return true }
        return currentCount + incomingCount <= freeItemLimit
    }
}

struct MembershipStatusSummary: Equatable {
    let accessLevel: MembershipAccessLevel
    let productIdentifier: String?
    let expirationDate: Date?
    let referenceDate: Date

    init(
        accessLevel: MembershipAccessLevel,
        productIdentifier: String?,
        expirationDate: Date?,
        referenceDate: Date = Date()
    ) {
        self.accessLevel = accessLevel
        self.productIdentifier = productIdentifier
        self.expirationDate = expirationDate
        self.referenceDate = referenceDate
    }

    var stateTitle: String {
        switch accessLevel {
        case .activePro:
            L.string("Pro Active")
        case .expiredReadOnly:
            L.string("Read-Only Protection")
        case .lockedUntilPro:
            L.string("Free Plan")
        }
    }

    var planTitle: String {
        guard let productIdentifier else {
            return accessLevel == .lockedUntilPro ? L.string("Free Plan") : L.string("Previous Pro")
        }
        return Self.localizedPlanName(forProductID: productIdentifier)
    }

    var formattedExpirationDate: String {
        guard let expirationDate else { return "" }
        return Self.expirationDateFormatter.string(from: expirationDate)
    }

    var expirationText: String {
        switch accessLevel {
        case .activePro:
            if productIdentifier == SubscriptionManager.lifetime {
                return L.string("Lifetime access")
            }
            guard expirationDate != nil else { return "" }
            return L.format("Valid until %@", formattedExpirationDate)
        case .expiredReadOnly:
            return L.string("Expired or inactive")
        case .lockedUntilPro:
            return L.string("No active membership")
        }
    }

    var detailText: String {
        switch accessLevel {
        case .activePro:
            L.string("You can add, edit, delete, and sync Mo Layer content.")
        case .expiredReadOnly:
            L.string("You can view existing Mo Layer content. Renew Pro to add or sync new content.")
        case .lockedUntilPro:
            L.format("Free vault includes up to %d photos, videos, audio, and files. Pro unlocks more imports, editing, and encrypted sync.", VaultFreeImportPolicy.freeItemLimit)
        }
    }

    static func localizedPlanName(forProductID productID: String) -> String {
        switch productID {
        case SubscriptionManager.monthly:
            L.string("Monthly Pro")
        case SubscriptionManager.yearly:
            L.string("Yearly Pro")
        case SubscriptionManager.lifetime:
            L.string("Lifetime Pro")
        default:
            L.string("Pro")
        }
    }

    private static var expirationDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
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
    nonisolated static let revenueCatProxyURL = URL(string: "https://api.rc-backup.com/")!
    nonisolated static let freeTrialDays = 3
    static var termsOfUseURL: URL {
        localizedLegalURL(englishPath: "en-US/content/terms-of-service/", chinesePath: "zh-Hans/content/terms-of-service/")
    }
    static var privacyPolicyURL: URL {
        localizedLegalURL(englishPath: "en-US/content/privacy-policy/", chinesePath: "zh-Hans/content/privacy-policy/")
    }
    nonisolated static var grantsDeveloperAccessInDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    private nonisolated static let revenueCatPlaceholderAPIKey = "REPLACE_WITH_REVENUECAT_PUBLIC_IOS_KEY"
    private nonisolated static let hasActivatedProStorageKey = "subscription.hasActivatedPro"

    private static func localizedLegalURL(englishPath: String, chinesePath: String) -> URL {
        let path: String
        switch AppLanguage.current {
        case .simplifiedChinese, .traditionalChinese:
            path = chinesePath
        case .system, .english, .japanese, .german, .french, .korean, .spanish:
            path = englishPath
        }
        return URL(string: "https://molayer.tech/\(path)")!
    }

    @Published var packages: [Package] = []
    @Published var missingProductIDs: [String] = []
    @Published var loadState: SubscriptionLoadState = .idle
    @Published var isPro = false
    @Published var statusText = L.string("Free Plan")
    @Published var restoreFeedback: RestorePurchaseFeedback?
    @Published private(set) var activeProductIdentifier: String?
    @Published private(set) var activeExpirationDate: Date?
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
        accessLevel.moLayerEntryAction == .enter
    }

    var canImportAndSync: Bool {
        accessLevel.allowsImportAndCloudSync
    }

    var canPullFromCloud: Bool {
        accessLevel.allowsCloudPull
    }

    var membershipStatusSummary: MembershipStatusSummary {
        MembershipStatusSummary(
            accessLevel: accessLevel,
            productIdentifier: activeProductIdentifier,
            expirationDate: activeExpirationDate
        )
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
            packages = fetchedPackages.filter { package in
                Self.expectedProductIDs.contains(package.storeProduct.productIdentifier)
            }.sorted { lhs, rhs in
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
        restoreFeedback = nil
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
        restoreFeedback = nil
        guard isRevenueCatReady else {
            let feedback = RestorePurchaseFeedback.failed()
            restoreFeedback = feedback
            statusText = feedback.message
            return
        }
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(customerInfo)
            let restoredActivePro = isPro
            restoreFeedback = RestorePurchaseFeedback.restored(hasActivePro: restoredActivePro)
            applyDeveloperAccessIfNeeded()
        } catch {
            let feedback = RestorePurchaseFeedback.failed()
            restoreFeedback = feedback
            statusText = feedback.message
            applyDeveloperAccessIfNeeded()
        }
    }

    func redeemOfferCode() async {
        restoreFeedback = nil
        guard isRevenueCatReady else {
            let feedback = RestorePurchaseFeedback.codeRedemptionUnavailable()
            restoreFeedback = feedback
            statusText = feedback.message
            applyDeveloperAccessIfNeeded()
            return
        }
        guard #available(iOS 14.0, *) else {
            let feedback = RestorePurchaseFeedback.codeRedemptionUnavailable()
            restoreFeedback = feedback
            statusText = feedback.message
            applyDeveloperAccessIfNeeded()
            return
        }

#if targetEnvironment(macCatalyst)
        let feedback = RestorePurchaseFeedback.codeRedemptionUnavailable()
        restoreFeedback = feedback
        statusText = feedback.message
        applyDeveloperAccessIfNeeded()
        return
#else
        Purchases.shared.presentCodeRedemptionSheet()
        statusText = L.string("Code redemption opened. Complete the App Store prompt, then Pro will refresh automatically.")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refreshEntitlements()
        restoreFeedback = RestorePurchaseFeedback.codeRedemptionOpened(hasActivePro: isPro)
        applyDeveloperAccessIfNeeded()
#endif
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
        let entitlement = customerInfo.entitlements[Self.revenueCatEntitlementID]
        let active = entitlement?.isActive == true
        isPro = active
        activeProductIdentifier = active ? entitlement?.productIdentifier : nil
        activeExpirationDate = active ? entitlement?.expirationDate : nil
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
        activeProductIdentifier = activeProductIdentifier ?? Self.lifetime
        activeExpirationDate = nil
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

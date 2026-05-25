import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let monthly = "privacy.vault.pro.monthly"
    static let yearly = "privacy.vault.pro.yearly"
    static let lifetime = "privacy.vault.pro.lifetime"

    @Published var products: [Product] = []
    @Published var isPro = false
    @Published var statusText = L.string("Free Plan")

    func load() async {
        do {
            products = try await Product.products(for: [Self.monthly, Self.yearly, Self.lifetime])
            await refreshEntitlements()
        } catch {
            statusText = L.string("Unable to load membership products")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            case .pending:
                statusText = L.string("Purchase Pending")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            statusText = L.string("Purchase Failed")
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if [Self.monthly, Self.yearly, Self.lifetime].contains(transaction.productID) {
                active = true
            }
        }
        isPro = active
        statusText = active ? L.string("Pro Active") : L.string("Free Plan")
    }
}

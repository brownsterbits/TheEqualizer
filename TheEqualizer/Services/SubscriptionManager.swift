import Foundation
import StoreKit
import SwiftUI

class SubscriptionManager: ObservableObject {
    @Published var isProUser = false
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var currentSubscription: String?

    private let productIds = ["pro_monthly", "pro_yearly"]
    private var products: [Product] = []
    private var transactionListener: Task<Void, Error>?

    enum SubscriptionStatus {
        case notSubscribed
        case pending
        case subscribed
        case expired
        case failed
    }

    init() {
        // Start listening for transaction updates
        transactionListener = listenForTransactions()

        // Load products and check status on BACKGROUND thread to avoid blocking UI
        Task.detached { [weak self] in
            await self?.loadProducts()
            await self?.checkSubscriptionStatus()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
        } catch {
            // Silent failure - products will remain empty
        }
    }
    
    var monthlyProduct: Product? {
        products.first { $0.id == "pro_monthly" }
    }
    
    var yearlyProduct: Product? {
        products.first { $0.id == "pro_yearly" }
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async {
        await MainActor.run {
            self.subscriptionStatus = .pending
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateSubscriptionStatus(for: transaction)
                await transaction.finish()

            case .userCancelled:
                await MainActor.run {
                    self.subscriptionStatus = .notSubscribed
                }

            case .pending:
                await MainActor.run {
                    self.subscriptionStatus = .notSubscribed
                }

            @unknown default:
                await MainActor.run {
                    self.subscriptionStatus = .failed
                }
            }
        } catch {
            await MainActor.run {
                self.subscriptionStatus = .failed
            }
        }
    }
    
    // MARK: - Subscription Status
    
    func checkSubscriptionStatus() async {
        var isActive = false
        var currentProductId: String?

        // Run StoreKit check on background thread (can be slow with network issues)
        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if productIds.contains(transaction.productID) {
                    // Check if still valid (not expired or revoked)
                    if transaction.revocationDate == nil {
                        isActive = true
                        currentProductId = transaction.productID
                    }
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }

        // Only hop to MainActor when updating @Published properties
        await MainActor.run {
            self.isProUser = isActive
            self.currentSubscription = currentProductId
            self.subscriptionStatus = isActive ? .subscribed : .notSubscribed
        }
    }
    
    // MARK: - Transaction Listening
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await updateSubscriptionStatus(for: transaction)
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    private func updateSubscriptionStatus(for transaction: StoreKit.Transaction) async {
        let isActive = productIds.contains(transaction.productID) && transaction.revocationDate == nil
        let productId = isActive ? transaction.productID : nil

        // Only hop to MainActor when updating @Published properties
        await MainActor.run {
            self.isProUser = isActive
            self.currentSubscription = productId
            self.subscriptionStatus = isActive ? .subscribed : .notSubscribed
        }
    }
    
    // MARK: - Verification
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
    
    // MARK: - Subscription Info
    
    var subscriptionDisplayName: String {
        guard let productId = currentSubscription else { return "Not Subscribed" }
        
        switch productId {
        case "pro_monthly":
            return "Pro Monthly"
        case "pro_yearly":
            return "Pro Yearly"
        default:
            return "Pro Subscription"
        }
    }
    
    var monthlyPrice: String {
        monthlyProduct?.displayPrice ?? "$1.99"
    }
    
    var yearlyPrice: String {
        yearlyProduct?.displayPrice ?? "$19.99"
    }
}

enum StoreKitError: Error {
    case failedVerification
}
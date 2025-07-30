import Foundation
import StoreKit
import SwiftUI

@MainActor
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
        
        Task {
            await loadProducts()
            await checkSubscriptionStatus()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
            print("DEBUG: Loaded \(products.count) products for IDs: \(productIds)")
            for product in products {
                print("DEBUG: Product - ID: \(product.id), Name: \(product.displayName), Price: \(product.displayPrice)")
            }
            if products.isEmpty {
                print("DEBUG: No products loaded! Check App Store Connect configuration for: \(productIds)")
            }
        } catch {
            print("DEBUG: Failed to load products: \(error)")
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
        print("DEBUG: Starting purchase for product: \(product.id)")
        subscriptionStatus = .pending
        
        do {
            print("DEBUG: Calling product.purchase()...")
            let result = try await product.purchase()
            print("DEBUG: Purchase result: \(result)")
            
            switch result {
            case .success(let verification):
                print("DEBUG: Purchase successful, verifying transaction...")
                let transaction = try checkVerified(verification)
                print("DEBUG: Transaction verified: \(transaction.productID)")
                await updateSubscriptionStatus(for: transaction)
                await transaction.finish()
                
            case .userCancelled:
                print("DEBUG: User cancelled purchase")
                subscriptionStatus = .notSubscribed
                
            case .pending:
                print("DEBUG: Purchase pending")
                subscriptionStatus = .notSubscribed
                
            @unknown default:
                print("DEBUG: Unknown purchase result")
                subscriptionStatus = .failed
            }
        } catch {
            print("DEBUG: Purchase failed with error: \(error)")
            subscriptionStatus = .failed
        }
    }
    
    // MARK: - Subscription Status
    
    func checkSubscriptionStatus() async {
        var isActive = false
        var currentProductId: String?
        
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
        
        isProUser = isActive
        currentSubscription = currentProductId
        subscriptionStatus = isActive ? .subscribed : .notSubscribed
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
        print("DEBUG: Updating subscription status for transaction: \(transaction.productID)")
        print("DEBUG: Product IDs: \(productIds)")
        print("DEBUG: Transaction revocation date: \(transaction.revocationDate?.description ?? "none")")
        
        if productIds.contains(transaction.productID) && transaction.revocationDate == nil {
            print("DEBUG: Setting user as Pro")
            isProUser = true
            currentSubscription = transaction.productID
            subscriptionStatus = .subscribed
        } else {
            print("DEBUG: Setting user as Free")
            isProUser = false
            currentSubscription = nil
            subscriptionStatus = .notSubscribed
        }
        
        print("DEBUG: Final status - isProUser: \(isProUser), subscriptionStatus: \(subscriptionStatus)")
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
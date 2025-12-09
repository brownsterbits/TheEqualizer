import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedProductId: String = "com.brownsterbits.theequalizer.pro.monthly" // Default to monthly - ALWAYS have selection
    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var showingPending = false
    @State private var isLoadingProducts = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                        
                        Text("Upgrade to Pro")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Unlock unlimited events and collaboration features")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(
                            icon: "calendar.badge.plus",
                            title: "Unlimited Events",
                            description: "Create as many events as you need"
                        )
                        
                        FeatureRow(
                            icon: "person.3.fill",
                            title: "Collaboration",
                            description: "Invite others to share expenses in real-time"
                        )
                        
                        FeatureRow(
                            icon: "icloud.and.arrow.up",
                            title: "Cloud Sync",
                            description: "Access your events from any device"
                        )
                        
                        FeatureRow(
                            icon: "lock.shield.fill",
                            title: "Priority Support",
                            description: "Get help when you need it"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Subscription Options
                    VStack(spacing: 12) {
                        if isLoadingProducts {
                            // Loading state
                            HStack {
                                ProgressView()
                                Text("Loading subscription options...")
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 120)
                        } else if subscriptionManager.productLoadError != nil && !subscriptionManager.hasProducts {
                            // Error state with retry
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                Text("Unable to load subscription options")
                                    .font(.headline)
                                Text("Please check your internet connection")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("Try Again") {
                                    Task {
                                        isLoadingProducts = true
                                        await subscriptionManager.loadProducts()
                                        isLoadingProducts = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                            }
                            .frame(height: 160)
                        } else {
                            // Monthly option - show even if product hasn't loaded
                            if let monthly = subscriptionManager.monthlyProduct {
                                SubscriptionOptionCard(
                                    product: monthly,
                                    isSelected: selectedProductId == "com.brownsterbits.theequalizer.pro.monthly",
                                    badge: nil
                                ) {
                                    selectedProductId = "com.brownsterbits.theequalizer.pro.monthly"
                                }
                            } else {
                                // Fallback UI when products haven't loaded
                                SubscriptionPlaceholderCard(
                                    title: "Pro Monthly",
                                    description: "Billed monthly",
                                    price: "$1.99/month",
                                    isSelected: selectedProductId == "com.brownsterbits.theequalizer.pro.monthly",
                                    badge: nil
                                ) {
                                    selectedProductId = "com.brownsterbits.theequalizer.pro.monthly"
                                }
                            }

                            // Yearly option - show even if product hasn't loaded
                            if let yearly = subscriptionManager.yearlyProduct {
                                SubscriptionOptionCard(
                                    product: yearly,
                                    isSelected: selectedProductId == "com.brownsterbits.theequalizer.pro.annual",
                                    badge: "SAVE 17%"
                                ) {
                                    selectedProductId = "com.brownsterbits.theequalizer.pro.annual"
                                }
                            } else {
                                // Fallback UI when products haven't loaded
                                SubscriptionPlaceholderCard(
                                    title: "Pro Yearly",
                                    description: "Billed annually",
                                    price: "$19.99/year",
                                    isSelected: selectedProductId == "com.brownsterbits.theequalizer.pro.annual",
                                    badge: "SAVE 17%"
                                ) {
                                    selectedProductId = "com.brownsterbits.theequalizer.pro.annual"
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Purchase Button - always enabled since we always have a default selection
                    Button(action: purchase) {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Subscribe Now")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(isPurchasing)
                    
                    // Terms
                    VStack(spacing: 8) {
                        Button("Restore Purchases") {
                            Task {
                                await subscriptionManager.restorePurchases()
                                if subscriptionManager.isProUser {
                                    dismiss()
                                }
                            }
                        }
                        .font(.footnote)
                        
                        Text("Cancel anytime from Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            Link("Terms of Service", destination: URL(string: "https://brownsterbits.github.io/TheEqualizer/terms.html")!)
                            Link("Privacy Policy", destination: URL(string: "https://brownsterbits.github.io/TheEqualizer/privacy.html")!)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Maybe Later") {
                        dismiss()
                    }
                }
            }
            .alert("Purchase Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Purchase Pending", isPresented: $showingPending) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your purchase is pending approval. Once approved, your Pro subscription will activate automatically.")
            }
            .overlay {
                if showingSuccess {
                    // Success overlay - shows checkmark before dismissing
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.green)

                            Text("Welcome to Pro!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Your subscription is now active")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(40)
                        .background(Color(.systemBackground).opacity(0.95))
                        .cornerRadius(20)
                        .shadow(radius: 20)
                    }
                    .transition(.opacity)
                }
            }
        }
        .navigationViewStyle(.stack) // Prevents iPad split view issues in sheets
        .presentationDetents([.large]) // Ensure full height on iPad
        .presentationDragIndicator(.visible) // Show drag indicator for clarity
        .task {
            // Load products when view appears if not already loaded
            if !subscriptionManager.hasProducts {
                isLoadingProducts = true
                await subscriptionManager.loadProducts()
                isLoadingProducts = false
            }
        }
    }
    
    private func purchase() {
        isPurchasing = true

        Task {
            // Look up the product by selectedProductId
            var productToPurchase: Product? = selectedProductId == "com.brownsterbits.theequalizer.pro.monthly"
                ? subscriptionManager.monthlyProduct
                : subscriptionManager.yearlyProduct

            // If product not loaded yet, try loading now
            if productToPurchase == nil {
                await subscriptionManager.loadProducts()
                productToPurchase = selectedProductId == "com.brownsterbits.theequalizer.pro.monthly"
                    ? subscriptionManager.monthlyProduct
                    : subscriptionManager.yearlyProduct
            }

            if let product = productToPurchase {
                let result = await subscriptionManager.purchaseWithResult(product)

                isPurchasing = false

                switch result {
                case .success:
                    // Show success animation before dismissing
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingSuccess = true
                    }
                    // Wait for user to see success message, then dismiss
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    dismiss()

                case .pending:
                    // User needs parental approval (Ask to Buy) or other pending state
                    showingPending = true

                case .cancelled:
                    // User cancelled - no action needed, they can try again
                    break

                case .failed:
                    errorMessage = "Unable to complete purchase. Please try again."
                    showingError = true
                }
            } else {
                // Products couldn't be loaded - show error to user with details
                isPurchasing = false
                if let loadError = subscriptionManager.productLoadError {
                    errorMessage = "Unable to load subscription options: \(loadError)"
                } else {
                    errorMessage = "Unable to connect to the App Store. Please check your internet connection and try again."
                }
                showingError = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.purple)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct SubscriptionOptionCard: View {
    let product: Product
    let isSelected: Bool
    let badge: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(product.displayPrice)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding()
            .background(isSelected ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Fallback card shown when StoreKit products haven't loaded yet
struct SubscriptionPlaceholderCard: View {
    let title: String
    let description: String
    let price: String
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)

                        if let badge = badge {
                            Text(badge)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(price)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding()
            .background(isSelected ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    
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
                        if let monthly = subscriptionManager.monthlyProduct {
                            SubscriptionOptionCard(
                                product: monthly,
                                isSelected: selectedProduct?.id == monthly.id,
                                badge: nil
                            ) {
                                selectedProduct = monthly
                            }
                        }
                        
                        if let yearly = subscriptionManager.yearlyProduct {
                            SubscriptionOptionCard(
                                product: yearly,
                                isSelected: selectedProduct?.id == yearly.id,
                                badge: "SAVE 17%"
                            ) {
                                selectedProduct = yearly
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Purchase Button
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
                        .background(selectedProduct != nil ? Color.purple : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(selectedProduct == nil || isPurchasing)
                    
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
                            Link("Terms of Service", destination: URL(string: "https://chadmbrown.github.io/the-equalizer-legal/terms.html")!)
                            Link("Privacy Policy", destination: URL(string: "https://chadmbrown.github.io/the-equalizer-legal/privacy.html")!)
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
        }
    }
    
    private func purchase() {
        guard let product = selectedProduct else { return }
        
        isPurchasing = true
        Task {
            await subscriptionManager.purchase(product)
            isPurchasing = false
            
            if subscriptionManager.isProUser {
                dismiss()
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
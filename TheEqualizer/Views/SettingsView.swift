import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var dataStore: DataStore
    @State private var showingPaywall = false
    
    var body: some View {
        List {
            // Subscription Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscriptionManager.isProUser ? "Pro Plan" : "Free Plan")
                            .font(.headline)
                        
                        if subscriptionManager.isProUser {
                            Text(subscriptionManager.subscriptionDisplayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("1 event limit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if subscriptionManager.isProUser {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                    } else {
                        Button("Upgrade") {
                            showingPaywall = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
                
                if !subscriptionManager.isProUser {
                    Button(action: { showingPaywall = true }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("See Pro Features")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.purple)
                }
            }
            
            // App Info Section
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                Link(destination: URL(string: "https://yourdomain.com/privacy")!) {
                    HStack {
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://yourdomain.com/terms")!) {
                    HStack {
                        Text("Terms of Service")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Support Section
            Section("Support") {
                Link(destination: URL(string: "mailto:support@yourdomain.com")!) {
                    HStack {
                        Text("Contact Support")
                        Spacer()
                        Image(systemName: "envelope")
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }) {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}
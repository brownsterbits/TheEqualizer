import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var dataStore: DataStore
    @State private var showingPaywall = false
    @State private var showingClearDataAlert = false
    
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
                
                Link(destination: URL(string: "https://chadmbrown.github.io/the-equalizer-legal/privacy.html")!) {
                    HStack {
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://chadmbrown.github.io/the-equalizer-legal/terms.html")!) {
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
            
            // Debug Section (temporary)
            Section("Debug") {
                Button(action: {
                    showingClearDataAlert = true
                }) {
                    HStack {
                        Text("Clear All Data")
                        Spacer()
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
                .foregroundColor(.red)
                
                Button(action: {
                    dataStore.resetToFreeUser()
                }) {
                    HStack {
                        Text("Reset to Free User (Keep Data)")
                        Spacer()
                        Image(systemName: "person.badge.minus")
                            .foregroundColor(.orange)
                    }
                }
                .foregroundColor(.orange)
                
                Button(action: {
                    // Debug: manually toggle Pro status to test sync
                    subscriptionManager.isProUser.toggle()
                    print("DEBUG: Manually toggled Pro status to: \(subscriptionManager.isProUser)")
                }) {
                    HStack {
                        Text("Debug: Toggle Pro Status")
                        Spacer()
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .foregroundColor(.blue)
                
                Button(action: {
                    dataStore.printDiagnostics()
                }) {
                    HStack {
                        Text("Debug: Print Diagnostics")
                        Spacer()
                        Image(systemName: "stethoscope")
                            .foregroundColor(.green)
                    }
                }
                .foregroundColor(.green)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .alert("Delete All Data?", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                dataStore.clearAllData()
            }
        } message: {
            Text("This will permanently delete ALL events, expenses, members, and donations. This action cannot be undone.\n\nAre you absolutely sure?")
        }
    }
}
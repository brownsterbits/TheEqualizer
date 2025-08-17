import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var selectedTab = 0
    @State private var refreshID = UUID()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Events tab - only show for Pro users
            if subscriptionManager.isProUser {
                NavigationView {
                    EventsListView()
                        .id("EventsListView-\(subscriptionManager.isProUser)")
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }
                .tag(0)
            }
            
            NavigationView {
                MembersView()
                    .id("MembersView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Members", systemImage: "person.3.fill")
            }
            .tag(subscriptionManager.isProUser ? 1 : 0)
            
            NavigationView {
                ExpensesView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Expenses", systemImage: "dollarsign.circle.fill")
            }
            .tag(subscriptionManager.isProUser ? 2 : 1)
            
            NavigationView {
                DonationsView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Treasury", systemImage: "gift.fill")
            }
            .tag(subscriptionManager.isProUser ? 3 : 2)
            
            NavigationView {
                SummaryView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Summary", systemImage: "chart.pie.fill")
            }
            .tag(subscriptionManager.isProUser ? 4 : 3)
            
            NavigationView {
                SettlementView()
                    .id("SettlementView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Settlement", systemImage: "equal.circle.fill")
            }
            .tag(subscriptionManager.isProUser ? 5 : 4)
            
            NavigationView {
                SettingsView()
                    .id("SettingsView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(subscriptionManager.isProUser ? 6 : 5)
        }
        .accentColor(.purple)
        .id("TabView-\(refreshID)")
        .onChange(of: subscriptionManager.isProUser) { oldValue, newValue in
            // Reset to appropriate first tab when subscription status changes
            selectedTab = newValue ? 0 : 0 // Events tab for Pro, Members tab for Free
            // Force refresh of navigation views
            refreshID = UUID()
        }
        .onChange(of: dataStore.currentEvent) { oldEvent, newEvent in
            if let _ = newEvent, !subscriptionManager.isProUser {
                // In free mode, after event creation, select Members tab and refresh
                selectedTab = 0
                refreshID = UUID()
            }
        }
        .onAppear {
            // Ensure selectedTab is valid on app start
            if !subscriptionManager.isProUser && selectedTab == 0 {
                selectedTab = 0 // Should be Members tab for free users
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ForceUIRefresh"))) { _ in
            // Force UI refresh when data is cleared/reset
            print("DEBUG: Forcing UI refresh due to data reset")
            refreshID = UUID()
            
            // Reset to appropriate first tab
            selectedTab = subscriptionManager.isProUser ? 0 : 0
        }
    }
}

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var selectedTab = 0
    @State private var refreshID = UUID()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Events tab - show for all users (Free users can create one event)
            NavigationView {
                EventsListView()
                    .id("EventsListView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Events", systemImage: "calendar")
            }
            .tag(0)
            
            NavigationView {
                MembersView()
                    .id("MembersView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Members", systemImage: "person.3.fill")
            }
            .tag(1)
            
            NavigationView {
                ExpensesView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Expenses", systemImage: "dollarsign.circle.fill")
            }
            .tag(2)
            
            NavigationView {
                DonationsView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Treasury", systemImage: "gift.fill")
            }
            .tag(3)
            
            NavigationView {
                SummaryView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Summary", systemImage: "chart.pie.fill")
            }
            .tag(4)
            
            NavigationView {
                SettlementView()
                    .id("SettlementView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Settlement", systemImage: "equal.circle.fill")
            }
            .tag(5)
            
            NavigationView {
                SettingsView()
                    .id("SettingsView-\(subscriptionManager.isProUser)")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(6)
        }
        .accentColor(.purple)
        .id("TabView-\(refreshID)")
        .onChange(of: subscriptionManager.isProUser) { oldValue, newValue in
            // Force refresh of navigation views when subscription status changes
            refreshID = UUID()
        }
        .onChange(of: dataStore.currentEvent) { oldEvent, newEvent in
            // Only navigate to Events tab when creating a NEW event (oldEvent was nil)
            // Don't navigate when just modifying the current event
            if oldEvent == nil && newEvent != nil && !subscriptionManager.isProUser {
                // In free mode, after event creation, stay on Events tab and refresh
                selectedTab = 0
                refreshID = UUID()
            }
        }
        .onAppear {
            // Start on Events tab for all users
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ForceUIRefresh"))) { _ in
            // Force UI refresh when data is cleared/reset
            refreshID = UUID()

            // Reset to first tab
            selectedTab = 0
        }
    }
}

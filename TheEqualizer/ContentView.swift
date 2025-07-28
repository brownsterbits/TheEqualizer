import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                MembersView()
            }
            .tabItem {
                Label("Members", systemImage: "person.3.fill")
            }
            .tag(0)
            
            NavigationView {
                ExpensesView()
            }
            .tabItem {
                Label("Expenses", systemImage: "dollarsign.circle.fill")
            }
            .tag(1)
            
            NavigationView {
                DonationsView()
            }
            .tabItem {
                Label("Donations", systemImage: "gift.fill")
            }
            .tag(2)
            
            NavigationView {
                SummaryView()
            }
            .tabItem {
                Label("Summary", systemImage: "chart.pie.fill")
            }
            .tag(3)
            
            NavigationView {
                SettlementView()
            }
            .tabItem {
                Label("Settlement", systemImage: "equal.circle.fill")
            }
            .tag(4)
            
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(5)
        }
        .accentColor(.purple)
    }
}
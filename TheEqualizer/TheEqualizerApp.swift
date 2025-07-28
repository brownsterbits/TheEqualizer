import SwiftUI

@main
struct TheEqualizerApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var subscriptionManager = SubscriptionManager()
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                EventView()
                    .environmentObject(dataStore)
                    .environmentObject(subscriptionManager)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .onAppear {
                // Sync subscription status with DataStore
                dataStore.subscriptionManager = subscriptionManager
            }
        }
    }
}
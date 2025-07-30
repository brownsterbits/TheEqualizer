import SwiftUI
import CloudKit

@main
struct TheEqualizerApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var subscriptionManager = SubscriptionManager()
    
    var body: some Scene {
        WindowGroup {
            EventView()
                .environmentObject(dataStore)
                .environmentObject(subscriptionManager)
                .onAppear {
                    // Sync subscription status with DataStore
                    dataStore.subscriptionManager = subscriptionManager
                }
                .onOpenURL { url in
                    // Handle CloudKit sharing URLs
                    Task {
                        do {
                            let metadata = try await CKContainer.default().shareMetadata(for: url)
                            try await dataStore.cloudKitService.acceptSharedEvent(from: metadata)
                            // Refresh events after accepting share
                            await dataStore.checkCloudKitStatus()
                        } catch {
                            print("Error handling CloudKit URL: \(error)")
                        }
                    }
                }
        }
    }
}

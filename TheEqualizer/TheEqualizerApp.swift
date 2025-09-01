import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct TheEqualizerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var dataStore = DataStore()
    @StateObject private var subscriptionManager = SubscriptionManager()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(dataStore)
                .environmentObject(dataStore.firebaseService)
                .environmentObject(subscriptionManager)
                .onAppear {
                    // Sync subscription status with DataStore
                    dataStore.subscriptionManager = subscriptionManager
                }
                .onOpenURL { url in
                    // Handle invite links for Firebase sharing
                    if url.scheme == "theequalizer" && url.host == "invite" {
                        if let inviteCode = url.pathComponents.last {
                            Task {
                                await dataStore.handleInviteCode(inviteCode)
                            }
                        }
                    }
                }
        }
    }
}

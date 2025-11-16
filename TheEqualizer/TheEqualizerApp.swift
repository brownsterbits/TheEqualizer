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
    @State private var isInitializing = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isInitializing {
                    // Show splash screen while initializing
                    VStack(spacing: 20) {
                        Image(systemName: "equal.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.purple)

                        Text("The Equalizer")
                            .font(.title)
                            .fontWeight(.bold)

                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    MainTabView()
                        .environmentObject(dataStore)
                        .environmentObject(dataStore.firebaseService)
                        .environmentObject(subscriptionManager)
                }
            }
            .onAppear {
                // Sync subscription status with DataStore
                dataStore.subscriptionManager = subscriptionManager

                // Give initialization time to complete (2 seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isInitializing = false
                    }
                }
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

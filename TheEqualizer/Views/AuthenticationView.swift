import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) var dismiss
    
    @State private var isSigningIn = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Logo or App Icon
                Image(systemName: "equal.square.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
                    .padding(.top, 50)
                
                // Title
                VStack(spacing: 8) {
                    Text("Sign In to The Equalizer")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Sync your events across all your devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Sign In Options
                VStack(spacing: 16) {
                    if firebaseService.user?.isAnonymous == true {
                        // Upgrade anonymous account
                        Text("Upgrade Your Account")
                            .font(.headline)
                            .padding(.bottom, 8)
                        
                        Text("Link your Apple ID to sync across devices and never lose your data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.email]
                            request.nonce = firebaseService.sha256(firebaseService.generateNonce())
                        } onCompletion: { result in
                            handleSignInWithApple(result, isLinking: true)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .padding(.horizontal)
                    } else {
                        // Fresh sign in
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.email]
                            request.nonce = firebaseService.sha256(firebaseService.generateNonce())
                        } onCompletion: { result in
                            handleSignInWithApple(result, isLinking: false)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .padding(.horizontal)
                        
                        // Continue without account (anonymous)
                        if !subscriptionManager.isProUser {
                            Button(action: signInAnonymously) {
                                Text("Continue Without Account")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                
                Spacer()
                
                // Privacy links
                HStack {
                    Link("Privacy Policy", destination: URL(string: "https://github.com/brownsterbits/TheEqualizer/blob/main/docs/privacy.html")!)
                    Text("•")
                        .foregroundColor(.secondary)
                    Link("Terms of Service", destination: URL(string: "https://github.com/brownsterbits/TheEqualizer/blob/main/docs/terms.html")!)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom)
            }
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
            .overlay(
                Group {
                    if isSigningIn {
                        ProgressView("Signing in...")
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 5)
                    }
                }
            )
            .alert("Sign In Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func handleSignInWithApple(_ result: Result<ASAuthorization, Error>, isLinking: Bool) {
        isSigningIn = true
        
        Task {
            do {
                switch result {
                case .success(let authorization):
                    if isLinking {
                        try await firebaseService.linkAnonymousToApple(authorization: authorization)
                    } else {
                        try await firebaseService.signInWithApple(authorization: authorization)
                    }
                    await MainActor.run {
                        isSigningIn = false
                        dismiss()
                    }
                case .failure(let error):
                    throw error
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func signInAnonymously() {
        isSigningIn = true
        
        Task {
            do {
                try await firebaseService.signInAnonymously()
                await MainActor.run {
                    isSigningIn = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
import SwiftUI

struct InviteShareView: View {
    let event: Event
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var firebaseService: FirebaseService
    @Environment(\.dismiss) var dismiss
    
    @State private var inviteCode: String?
    @State private var isGenerating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""
    
    // Computed property to get the latest event data
    private var currentEventData: Event? {
        if let currentEvent = dataStore.currentEvent, currentEvent.id == event.id {
            return currentEvent
        }
        return dataStore.events.first { $0.id == event.id }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Share Event")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Invite others to collaborate on '\(event.name)'")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                if let code = inviteCode {
                    // Show invite code
                    VStack(spacing: 16) {
                        Text("Invite Code")
                            .font(.headline)
                        
                        Text(code)
                            .font(.system(.largeTitle, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        
                        Text((currentEventData?.inviteCode ?? event.inviteCode) != nil ? "This event already has an invite code" : "Share this code with others so they can join your event")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        // Copy button
                        Button(action: copyCode) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Code")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        // Share button
                        Button(action: shareCode) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    // Generate invite code
                    VStack(spacing: 16) {
                        if isGenerating {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text(statusMessage.isEmpty ? "Preparing to share..." : statusMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        } else {
                            Button(action: generateInviteCode) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Generate Invite Code")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding()
                        }
                    }
                }
                
                Spacer()
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works:")
                        .font(.headline)
                    
                    HStack(alignment: .top) {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text("Generate an invite code for this event")
                    }
                    .font(.caption)
                    
                    HStack(alignment: .top) {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text("Share the code with others")
                    }
                    .font(.caption)
                    
                    HStack(alignment: .top) {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text("They can join by entering the code in their app")
                    }
                    .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .navigationTitle("Share Event")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .onAppear {
            // If event already has an invite code, show it
            if let existingCode = currentEventData?.inviteCode ?? event.inviteCode {
                inviteCode = existingCode
            }
        }
        .onChange(of: currentEventData?.inviteCode) { oldValue, newValue in
            // Update the displayed code when it changes
            if let newCode = newValue {
                inviteCode = newCode
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func generateInviteCode() {
        isGenerating = true
        statusMessage = ""
        
        Task {
            // Update status as we progress
            if !firebaseService.isAuthenticated {
                await MainActor.run {
                    statusMessage = "Connecting to cloud..."
                }
            }
            
            if event.firebaseId == nil {
                await MainActor.run {
                    statusMessage = "Uploading event..."
                }
            }
            
            let code = await dataStore.shareEvent(event)
            
            await MainActor.run {
                isGenerating = false
                statusMessage = ""
                if let code = code {
                    inviteCode = code
                } else {
                    errorMessage = dataStore.syncError ?? "Failed to generate invite code. Please try again."
                    showingError = true
                }
            }
        }
    }
    
    private func copyCode() {
        guard let code = inviteCode else { return }
        UIPasteboard.general.string = code
        
        // Show feedback (you could add a toast notification here)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func shareCode() {
        guard let code = inviteCode else { return }
        
        let shareText = "Join my event '\(event.name)' in The Equalizer app using invite code: \(code)"
        let activityController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            // For iPad
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(activityController, animated: true)
        }
    }
}
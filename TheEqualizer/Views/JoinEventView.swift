import SwiftUI

struct JoinEventView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    @State private var inviteCode = ""
    @State private var isJoining = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Join Event")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Enter the invite code shared with you to join an event")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Input Section
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite Code")
                            .font(.headline)
                        
                        TextField("Enter 6-character code", text: $inviteCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.title3, design: .monospaced))
                            .textCase(.uppercase)
                            .autocorrectionDisabled()
                            .onChange(of: inviteCode) { _, newValue in
                                // Limit to 6 characters and uppercase
                                let filtered = String(newValue.uppercased().prefix(6).filter { $0.isLetter || $0.isNumber })
                                if filtered != newValue {
                                    inviteCode = filtered
                                }
                            }
                    }
                    
                    Button(action: joinEvent) {
                        HStack {
                            if isJoining {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Joining...")
                            } else {
                                Image(systemName: "person.badge.plus")
                                Text("Join Event")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(inviteCode.count == 6 ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(inviteCode.count != 6 || isJoining)
                }
                .padding()
                
                Spacer()
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get an invite code:")
                        .font(.headline)
                    
                    HStack(alignment: .top) {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text("Ask the event creator to share their event")
                    }
                    .font(.caption)
                    
                    HStack(alignment: .top) {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text("They'll get a 6-character code to share with you")
                    }
                    .font(.caption)
                    
                    HStack(alignment: .top) {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text("Enter that code here to join the event")
                    }
                    .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Join Event")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
        }
        .alert("Success!", isPresented: $showingSuccess) {
            Button("OK") { 
                dismiss()
            }
        } message: {
            Text("You've successfully joined the event!")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func joinEvent() {
        guard inviteCode.count == 6 else { return }
        
        isJoining = true
        
        Task {
            let success = await dataStore.handleInviteCode(inviteCode)
            
            await MainActor.run {
                isJoining = false
                if success {
                    showingSuccess = true
                } else {
                    errorMessage = dataStore.syncError ?? "Invalid invite code or unable to join event. Please check the code and try again."
                    showingError = true
                }
            }
        }
    }
}
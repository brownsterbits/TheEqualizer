import SwiftUI

struct EventView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var showingCreateEvent = false
    @State private var showingAuthSheet = false
    @State private var showingPaywall = false
    @State private var showingJoinEvent = false
    @State private var newEventName = ""
    
    var body: some View {
        if dataStore.currentEvent == nil {
            // No event - show improved onboarding
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "equal.square.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.purple)
                    
                    Text("Welcome to The Equalizer")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Split expenses fairly among groups")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: { showingCreateEvent = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Your First Event")
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // Show Join Event option for Pro users even without events
                    if subscriptionManager.isProUser {
                        Button(action: { 
                            if firebaseService.isAuthenticated {
                                showingJoinEvent = true
                            } else {
                                showingAuthSheet = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Join Event with Code")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    
                    Button(action: { showingAuthSheet = true }) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                            Text("Sign In to Sync Existing Events")
                        }
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: { 
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Restore Pro Subscription")
                        }
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(12)
                    }
                    
                    Button(action: { showingPaywall = true }) {
                        HStack {
                            Image(systemName: "star.circle.fill")
                            Text("See Pro Features")
                        }
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventView(eventName: $newEventName, isPresented: $showingCreateEvent) {
                    dataStore.createEvent(name: newEventName)
                    newEventName = ""
                }
            }
            .sheet(isPresented: $showingAuthSheet) {
                AuthenticationView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingJoinEvent) {
                JoinEventView()
            }
        } else {
            // Has event - show normal content
            VStack(spacing: 0) {
                // Event header bar
                EventHeaderView()
                
                MainTabView()
            }
        }
    }
}

struct EventHeaderView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingRenameEvent = false
    @State private var showingDeleteConfirmation = false
    @State private var newEventName = ""
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dataStore.currentEvent?.name ?? "Event")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if !dataStore.isPro {
                    Text("Free Plan")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: { 
                    newEventName = dataStore.currentEvent?.name ?? ""
                    showingRenameEvent = true 
                }) {
                    Label("Rename Event", systemImage: "pencil")
                }
                
                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete Event", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(UIColor.separator)),
            alignment: .bottom
        )
        .sheet(isPresented: $showingRenameEvent) {
            RenameEventView(eventName: $newEventName, isPresented: $showingRenameEvent) {
                dataStore.renameCurrentEvent(to: newEventName)
            }
        }
        .alert("Delete Event?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                dataStore.deleteCurrentEvent()
            }
        } message: {
            Text("This will permanently delete all data for this event. Make sure to export your settlement first!")
        }
    }
}

struct CreateEventView: View {
    @Binding var eventName: String
    @Binding var isPresented: Bool
    let onCreate: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Event Name", text: $eventName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Text("Give your event a name like \"Summer Trip\" or \"Office Party\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Create Event")
            .navigationBarItems(
                leading: Button("Cancel") {
                    eventName = ""
                    isPresented = false
                },
                trailing: Button("Create") {
                    onCreate()
                    isPresented = false
                }
                .fontWeight(.bold)
                .disabled(eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
}

struct RenameEventView: View {
    @Binding var eventName: String
    @Binding var isPresented: Bool
    let onRename: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Name")) {
                    TextField("Event Name", text: $eventName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .navigationTitle("Rename Event")
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Save") {
                    onRename()
                    isPresented = false
                }
                .fontWeight(.bold)
                .disabled(eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
}

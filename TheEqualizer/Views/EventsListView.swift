import SwiftUI

struct EventsListView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingCreateEvent = false
    @State private var showingDeleteAlert = false
    @State private var eventToDelete: Event?
    @State private var newEventName = ""
    @State private var showingPaywall = false
    @State private var showingAuthSheet = false
    @State private var showingInviteSheet = false
    @State private var selectedEventForInvite: Event?
    @State private var showingJoinSheet = false
    
    var body: some View {
        List {
            if !subscriptionManager.isProUser {
                // Free tier - single event
                Section {
                    if let currentEvent = dataStore.currentEvent {
                        EventRowView(event: currentEvent, isCurrent: true)
                    } else {
                        Button(action: { showingCreateEvent = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.purple)
                                Text("Create Your First Event")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        
                        Button(action: { showingAuthSheet = true }) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Sign In to Sync Existing Events")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        
                        Button(action: { 
                            Task {
                                await subscriptionManager.restorePurchases()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundColor(.green)
                                Text("Restore Pro Subscription")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                
                // Upgrade prompt
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upgrade to Pro")
                            .font(.headline)
                            .foregroundColor(.purple)
                        
                        Text("Create unlimited events and sync across devices with Firebase")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("See Pro Features") {
                            showingPaywall = true
                        }
                        .font(.caption)
                        .foregroundColor(.purple)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                // Pro tier - multiple events
                Section(header: Text("Your Events")) {
                    ForEach(dataStore.events) { event in
                        EventRowView(
                            event: event,
                            isCurrent: dataStore.currentEvent?.id == event.id
                        )
                        .swipeActions(edge: .leading) {
                            if dataStore.isFirebaseConnected {
                                Button {
                                    if !firebaseService.isAuthenticated {
                                        showingAuthSheet = true
                                    } else {
                                        // Set the selected event first
                                        selectedEventForInvite = event
                                        // Small delay to ensure state is set
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            showingInviteSheet = true
                                        }
                                    }
                                } label: {
                                    Label("Share", systemImage: "person.badge.plus")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                eventToDelete = event
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            dataStore.selectEvent(event)
                        }
                    }
                    
                    Button(action: { showingCreateEvent = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.purple)
                            Text("Create New Event")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    
                    Button(action: { 
                        if firebaseService.isAuthenticated {
                            showingJoinSheet = true
                        } else {
                            showingAuthSheet = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                            Text("Join Event with Code")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
                
                // Sharing instructions for Pro users with events
                if subscriptionManager.isProUser && !dataStore.events.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                    .foregroundColor(.purple)
                                Text("How to Share Events")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            Text("• Swipe right on any event to share with others")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("• Share the 6-character code with others")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("• They can join using 'Join Event with Code'")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Firebase sync status
                if subscriptionManager.isProUser {
                    Section {
                        if dataStore.isFirebaseConnected {
                            HStack {
                                Image(systemName: dataStore.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                                    .foregroundColor(dataStore.isSyncing ? .orange : .green)
                                Text(dataStore.isSyncing ? "Syncing..." : "Synced with Firebase")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.orange)
                                    Text("Not Connected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button("Sign In to Sync") {
                                    showingAuthSheet = true
                                }
                                .font(.caption2)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        if let error = dataStore.syncError {
                            Text("Sync Error: \(error)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(
                eventName: $newEventName,
                isPresented: $showingCreateEvent
            ) {
                dataStore.createEvent(name: newEventName)
                newEventName = ""
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingAuthSheet) {
            AuthenticationView()
        }
        .sheet(isPresented: $showingInviteSheet) {
            if let event = selectedEventForInvite {
                InviteShareView(event: event)
                    .environmentObject(dataStore)
                    .environmentObject(firebaseService)
                    .environmentObject(subscriptionManager)
            } else {
                // Debug: Show error if event is nil
                VStack {
                    Text("Error: No event selected")
                        .foregroundColor(.red)
                    Button("Close") {
                        showingInviteSheet = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingJoinSheet) {
            JoinEventView()
        }
        .alert("Delete Event", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                eventToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let event = eventToDelete {
                    dataStore.deleteEvent(event)
                }
                eventToDelete = nil
            }
        } message: {
            if let event = eventToDelete {
                Text("Are you sure you want to delete '\(event.name)'? This action cannot be undone.")
            }
        }
    }
}

struct EventRowView: View {
    let event: Event
    let isCurrent: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.name)
                        .font(.headline)
                    
                    if isCurrent {
                        Text("Current")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                Text("Last modified: \(event.lastModified, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if event.inviteCode != nil {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("Shared")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(event.members.count) members")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(event.expenses.count) expenses")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if event.totalExpenses > 0 {
                    Text("$\(event.totalExpenses, specifier: "%.2f")")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }
                
                // Show share status
                if event.inviteCode != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("Shared")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}


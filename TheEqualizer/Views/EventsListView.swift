import SwiftUI
import CloudKit

struct EventsListView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingCreateEvent = false
    @State private var showingDeleteAlert = false
    @State private var eventToDelete: Event?
    @State private var newEventName = ""
    @State private var showingPaywall = false
    
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
                    }
                }
                
                // Upgrade prompt
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upgrade to Pro")
                            .font(.headline)
                            .foregroundColor(.purple)
                        
                        Text("Create unlimited events and sync across devices with CloudKit")
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                eventToDelete = event
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !event.isShared && dataStore.isCloudKitEnabled {
                                Button {
                                    Task {
                                        if let share = await dataStore.shareEvent(event) {
                                            // Present share sheet
                                            await MainActor.run {
                                                presentShareSheet(share: share)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Share", systemImage: "person.badge.plus")
                                }
                                .tint(.blue)
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
                }
                
                // CloudKit status and sharing instructions
                if dataStore.isCloudKitEnabled {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .foregroundColor(.blue)
                                Text("Syncing with iCloud")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            HStack {
                                Image(systemName: "person.badge.plus")
                                    .foregroundColor(.purple)
                                Text("Swipe left on any event to share with others")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                } else if subscriptionManager.isProUser {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "icloud.slash")
                                    .foregroundColor(.orange)
                                Text("iCloud Sync Unavailable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Check your iCloud settings to enable sync and collaboration")
                                .font(.caption2)
                                .foregroundColor(.secondary)
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
    
    private func presentShareSheet(share: CKShare) {
        let controller = CloudSharingController(share: share, container: CKContainer.default())
        controller.modalPresentationStyle = .formSheet
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(controller, animated: true)
        }
    }
}

// MARK: - CloudKit Sharing Support

class CloudSharingController: UICloudSharingController {
    override init(share: CKShare, container: CKContainer) {
        super.init(share: share, container: container)
        delegate = self
    }
}

extension CloudSharingController: UICloudSharingControllerDelegate {
    func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Failed to save share: \(error)")
    }
    
    func itemTitle(for controller: UICloudSharingController) -> String? {
        return "Event Collaboration"
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
                
                if event.isShared {
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
                if event.isShared {
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


import SwiftUI

struct EventView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingCreateEvent = false
    @State private var showingRenameEvent = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPaywall = false
    @State private var newEventName = ""
    
    var body: some View {
        if dataStore.currentEvent == nil {
            // No event - show create button
            VStack(spacing: 20) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                
                Text("No Event Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first event to start tracking expenses")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button(action: { showingCreateEvent = true }) {
                    Text("Create Event")
                        .fontWeight(.semibold)
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventView(eventName: $newEventName, isPresented: $showingCreateEvent) {
                    dataStore.createEvent(name: newEventName)
                    newEventName = ""
                }
            }
        } else {
            // Has event - show normal content
            ContentView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(dataStore.currentEvent?.name ?? "Event")
                                .font(.headline)
                            
                            if !dataStore.isPro {
                                Text("Free Plan")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
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
                        }
                    }
                }
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
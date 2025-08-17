import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class DataStore: ObservableObject {
    @Published var currentEvent: Event?
    @Published var events: [Event] = []
    @Published var hasUnsavedChanges = false
    @Published var isPro = false
    @Published var isFirebaseConnected = false
    @Published var isSyncing = false
    @Published var syncError: String?
    
    let firebaseService: FirebaseService
    private var eventListener: ListenerRegistration?
    private var currentEventFirebaseId: String?
    private var isLocalUpdate = false  // Track when we're making local changes
    
    weak var subscriptionManager: SubscriptionManager? {
        didSet {
            setupSubscriptionSync()
        }
    }
    
    private func setupSubscriptionSync() {
        guard let manager = subscriptionManager else { return }
        
        // Initial sync
        Task { @MainActor in
            let wasProBefore = isPro
            isPro = manager.isProUser
            print("DEBUG: Initial sync - wasProBefore: \(wasProBefore), isPro: \(isPro), manager.isProUser: \(manager.isProUser)")
            
            // If just became Pro, preserve current event and add to events list
            if !wasProBefore && isPro {
                handleProUpgrade()
            }
        }
        
        // Set up ongoing sync by observing the subscription manager's isProUser property
        Task { @MainActor in
            for await _ in manager.$isProUser.values {
                let wasProBefore = isPro
                isPro = manager.isProUser
                print("DEBUG: Subscription status changed - wasProBefore: \(wasProBefore), isPro: \(isPro), manager.isProUser: \(manager.isProUser)")
                
                if !wasProBefore && isPro {
                    handleProUpgrade()
                } else if wasProBefore && !isPro {
                    handleProDowngrade()
                }
                
                saveData()
            }
        }
    }
    
    private func handleProUpgrade() {
        print("DEBUG: User upgraded to Pro")
        print("DEBUG: Current event before upgrade: \(currentEvent?.name ?? "nil")")
        
        // Ensure current event is preserved in events list
        if let current = currentEvent {
            if !events.contains(where: { $0.id == current.id }) {
                events.append(current)
                print("DEBUG: Added current event to events list: \(current.name)")
            }
        }
        
        // Save the state
        saveData()
        repairMissingEvents()
        
        // Sync with Firebase if authenticated
        if firebaseService.isAuthenticated {
            Task {
                await syncWithFirebase()
            }
        }
    }
    
    private func handleProDowngrade() {
        print("DEBUG: User downgraded from Pro")
        
        // Clear events list but keep current event
        events = []
        
        saveData()
    }
    
    private let eventKey = "TheEqualizerEvent"
    private let eventsKey = "TheEqualizerEvents"
    private let proKey = "TheEqualizerProStatus"
    
    init() {
        firebaseService = FirebaseService()
        loadData()
        
        // Debug: Try to repair missing events on init
        if isPro {
            repairMissingEvents()
        }
        
        // Setup Firebase auth listener
        setupFirebaseListener()
    }
    
    // MARK: - Firebase Integration
    
    private func setupFirebaseListener() {
        // Listen to auth state changes
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isFirebaseConnected = user != nil
                if user != nil && self?.isPro == true {
                    await self?.syncWithFirebase()
                }
            }
        }
    }
    
    @MainActor
    private func syncWithFirebase() async {
        guard firebaseService.isAuthenticated && isPro else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Fetch events from Firebase
            let firebaseEvents = try await firebaseService.fetchEvents()
            print("DEBUG: Fetched \(firebaseEvents.count) events from Firebase")
            
            // Merge with local events - prefer local data for UI consistency
            var mergedEvents: [Event] = []
            var processedIds = Set<UUID>()
            
            // First, add all local events (they have the most recent local changes)
            for localEvent in events {
                mergedEvents.append(localEvent)
                processedIds.insert(localEvent.id)
            }
            
            // Then add Firebase events that we don't have locally (shared from other devices)
            for firebaseEvent in firebaseEvents {
                // Check by UUID to prevent duplicates
                if !processedIds.contains(firebaseEvent.id) {
                    mergedEvents.append(firebaseEvent)
                    processedIds.insert(firebaseEvent.id)
                    print("DEBUG: Added new shared event from Firebase: \(firebaseEvent.name)")
                }
            }
            
            // Upload local events that aren't in Firebase (in background)
            Task.detached { [weak self] in
                guard let self = self else { return }
                
                for localEvent in self.events {
                    // Check if this event needs to be uploaded (no Firebase ID yet)
                    if localEvent.firebaseId == nil {
                        do {
                            print("DEBUG: Uploading local event '\(localEvent.name)' to Firebase")
                            let firebaseId = try await self.firebaseService.createEvent(localEvent)
                            
                            // Update local event with Firebase ID on main thread
                            await MainActor.run {
                                if let index = self.events.firstIndex(where: { $0.id == localEvent.id }) {
                                    self.events[index].firebaseId = firebaseId
                                    
                                    // Update current event if it matches
                                    if self.currentEvent?.id == localEvent.id {
                                        self.currentEvent?.firebaseId = firebaseId
                                    }
                                    
                                    self.saveData()
                                }
                            }
                        } catch {
                            print("Error uploading event to Firebase: \(error)")
                            // Continue with other events even if one fails
                        }
                    }
                }
            }
            
            // Remove any duplicates before updating (cleanup for existing bug)
            var cleanedEvents: [Event] = []
            var seenIds = Set<UUID>()
            
            for event in mergedEvents {
                if !seenIds.contains(event.id) {
                    cleanedEvents.append(event)
                    seenIds.insert(event.id)
                } else {
                    print("DEBUG: Removed duplicate event: \(event.name) with ID: \(event.id)")
                }
            }
            
            // Update events list
            self.events = cleanedEvents
            
            // If no current event, set to first available
            if currentEvent == nil && !events.isEmpty {
                currentEvent = events.first
            }
            
            // Setup real-time listener for current event
            if let currentEvent = currentEvent, let firebaseId = currentEvent.firebaseId {
                setupEventListener(firebaseId: firebaseId)
            }
            
            // Save locally immediately
            saveData()
            
            hasUnsavedChanges = false
            isSyncing = false
        } catch {
            print("Error syncing with Firebase: \(error)")
            syncError = error.localizedDescription
            isSyncing = false
            
            // Don't let sync failures affect local functionality
            // Data persists locally and will sync when connection improves
        }
    }
    
    private func setupEventListener(firebaseId: String) {
        // Remove existing listener
        eventListener?.remove()
        
        // Setup new listener - ONLY for changes from other users
        eventListener = firebaseService.listenToEvent(eventId: firebaseId) { [weak self] event in
            guard let self = self, var event = event else { return }
            
            // Ensure UI updates happen on main thread
            Task { @MainActor in
                // Skip if we're syncing (our own changes)
                if self.isSyncing {
                    print("DEBUG: Skipping real-time update - currently syncing our changes")
                    return
                }
                
                // Only accept updates that are newer than our local version
                if let currentEvent = self.currentEvent,
                   currentEvent.firebaseId == firebaseId {
                    
                    // If we have unsaved changes, don't overwrite them
                    if self.hasUnsavedChanges {
                        print("DEBUG: Skipping real-time update - we have unsaved changes")
                        return
                    }
                    
                    // Only update if Firebase version is newer
                    if event.lastModified <= currentEvent.lastModified {
                        print("DEBUG: Skipping older Firebase update")
                        return
                    }
                }
                
                // Preserve the Firebase ID and local UUID
                event.firebaseId = firebaseId
                if let currentEvent = self.currentEvent, currentEvent.firebaseId == firebaseId {
                    event.id = currentEvent.id  // Preserve local UUID
                }
                
                // Update current event
                if self.currentEvent?.firebaseId == firebaseId {
                    self.currentEvent = event
                    print("DEBUG: Updated current event from real-time listener (from other user)")
                }
                
                // Update in events list
                if let index = self.events.firstIndex(where: { $0.firebaseId == firebaseId }) {
                    event.id = self.events[index].id  // Preserve local UUID
                    self.events[index] = event
                }
                
                // Save changes locally (these are from other users)
                self.saveData()
            }
        }
    }
    
    private func saveToFirebase() {
        guard firebaseService.isAuthenticated, 
              let event = currentEvent,
              isPro else { return }
        
        // Save in background - don't block UI
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                await MainActor.run {
                    self.isSyncing = true
                }
                
                if let firebaseId = event.firebaseId {
                    // Update existing event
                    try await self.firebaseService.updateEvent(event, eventId: firebaseId)
                    print("DEBUG: Updated event '\(event.name)' in Firebase")
                } else {
                    // Create new event
                    let firebaseId = try await self.firebaseService.createEvent(event)
                    print("DEBUG: Created new event '\(event.name)' in Firebase with ID: \(firebaseId)")
                    
                    await MainActor.run {
                        self.currentEvent?.firebaseId = firebaseId
                        if let index = self.events.firstIndex(where: { $0.id == event.id }) {
                            self.events[index].firebaseId = firebaseId
                        }
                        self.saveData() // Save the Firebase ID locally
                    }
                }
                
                await MainActor.run {
                    self.hasUnsavedChanges = false
                    self.isSyncing = false
                }
            } catch {
                await MainActor.run {
                    self.syncError = error.localizedDescription
                    self.isSyncing = false
                }
                print("Error saving to Firebase: \(error)")
                // Don't fail - data is still saved locally
            }
        }
    }
    
    // MARK: - Computed Properties (redirect to current event)
    
    var members: [Member] {
        currentEvent?.members ?? []
    }
    
    var expenses: [Expense] {
        currentEvent?.expenses ?? []
    }
    
    var donations: [Donation] {
        currentEvent?.donations ?? []
    }
    
    var contributingMembers: [Member] {
        currentEvent?.contributingMembers ?? []
    }
    
    var reimbursementMembers: [Member] {
        currentEvent?.reimbursementMembers ?? []
    }
    
    var totalExpenses: Double {
        currentEvent?.totalExpenses ?? 0
    }
    
    var reimbursableExpenses: Double {
        currentEvent?.reimbursableExpenses ?? 0
    }
    
    var totalDonations: Double {
        currentEvent?.totalDonations ?? 0
    }
    
    var directContributions: Double {
        currentEvent?.directContributions ?? 0
    }
    
    var sharePerPerson: Double {
        currentEvent?.sharePerPerson ?? 0
    }
    
    // MARK: - Event Management
    
    func createEvent(name: String) {
        // State transition guard: Free users can only have one event
        if !isPro && (currentEvent != nil || !events.isEmpty) {
            print("WARNING: Free user attempting to create multiple events")
            return
        }
        
        // State transition guard: Validate event name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            print("WARNING: Attempting to create event with empty name")
            return
        }
        
        let newEvent = Event(name: trimmedName)
        currentEvent = newEvent
        
        if isPro {
            events.append(newEvent)
        }
        
        hasUnsavedChanges = true
        
        // Save locally immediately - this ensures UI persistence
        saveData()
        
        // Trigger navigation health check after state change
        let _ = performNavigationHealthCheck()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func selectEvent(_ event: Event) {
        // State transition guard: Only Pro users can select events
        guard isPro else { 
            print("WARNING: Free user attempting to select event")
            return 
        }
        
        currentEvent = event
        currentEventFirebaseId = event.firebaseId
        
        // Setup real-time listener if event has Firebase ID
        if let firebaseId = event.firebaseId {
            setupEventListener(firebaseId: firebaseId)
        }
        
        // Trigger navigation health check after state change
        let _ = performNavigationHealthCheck()
        
        saveData()
    }
    
    func deleteEvent(_ event: Event) {
        // State transition guard: For Pro users, validate event exists in events array
        // For Free users, validate it's the current event
        if isPro {
            guard events.contains(where: { $0.id == event.id }) else {
                print("WARNING: Pro user attempting to delete non-existent event")
                return
            }
        } else {
            guard currentEvent?.id == event.id else {
                print("WARNING: Free user attempting to delete non-current event")
                return
            }
        }
        
        // Remove event listener BEFORE deleting to prevent restoration
        if currentEvent?.id == event.id {
            eventListener?.remove()
            eventListener = nil
        }
        
        // Remove from local arrays (Pro users only)
        if isPro {
            events.removeAll { $0.id == event.id }
        }
        
        // Clear current event if it's the one being deleted
        if currentEvent?.id == event.id {
            if isPro {
                currentEvent = events.first
                // Setup listener for new current event if it has Firebase ID
                if let newEvent = currentEvent, let firebaseId = newEvent.firebaseId {
                    setupEventListener(firebaseId: firebaseId)
                }
            } else {
                // Free user - clear current event completely
                currentEvent = nil
            }
        }
        
        // Save data IMMEDIATELY before Firebase delete
        saveData()
        
        // Trigger navigation health check after state change
        let _ = performNavigationHealthCheck()
        
        // Delete from Firebase (do this LAST)
        if let firebaseId = event.firebaseId, firebaseService.isAuthenticated {
            Task {
                do {
                    try await firebaseService.deleteEvent(eventId: firebaseId)
                    print("DEBUG: Successfully deleted event from Firebase: \(event.name)")
                } catch {
                    print("ERROR: Failed to delete event from Firebase: \(error)")
                }
            }
        }
    }
    
    func deleteCurrentEvent() {
        guard let event = currentEvent else { return }
        deleteEvent(event)
    }
    
    @MainActor
    func shareEvent(_ event: Event) async -> String? {
        guard firebaseService.isAuthenticated,
              let firebaseId = event.firebaseId else { return nil }
        
        do {
            let inviteCode = try await firebaseService.createInviteCode(for: firebaseId)
            
            // Update the event's invite code
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index].inviteCode = inviteCode
            }
            if currentEvent?.id == event.id {
                currentEvent?.inviteCode = inviteCode
            }
            
            saveData()
            return inviteCode
        } catch {
            print("Error creating invite code: \(error)")
            return nil
        }
    }
    
    @MainActor
    func handleInviteCode(_ code: String) async {
        guard firebaseService.isAuthenticated else { return }
        
        do {
            let _ = try await firebaseService.joinEventWithCode(code)
            // Refresh events to include the newly joined event
            await syncWithFirebase()
        } catch {
            print("Error joining event with code: \(error)")
        }
    }
    
    func renameCurrentEvent(to newName: String) {
        currentEvent?.name = newName
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    // MARK: - Member Management
    
    func addMember(name: String, type: MemberType) {
        guard currentEvent != nil else { return }
        
        let member = Member(name: name, type: type)
        currentEvent?.members.append(member)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately - this ensures UI persistence
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func removeMember(_ member: Member) {
        guard currentEvent != nil else { return }
        
        currentEvent?.members.removeAll { $0.id == member.id }
        
        // Remove expenses paid by this member
        currentEvent?.expenses.removeAll { $0.paidBy == member.name }
        
        // Remove contributions made by this member
        if let expenses = currentEvent?.expenses {
            for i in expenses.indices {
                currentEvent?.expenses[i].contributors.removeAll { $0.name == member.name }
            }
        }
        
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func memberExists(name: String) -> Bool {
        currentEvent?.members.contains { $0.name == name } ?? false
    }
    
    // MARK: - Expense Management
    
    func addExpense(description: String, amount: Double, paidBy: String, notes: String, optOut: Bool) {
        guard currentEvent != nil else { return }
        
        let expense = Expense(
            description: description,
            amount: amount,
            paidBy: paidBy,
            notes: notes,
            optOut: optOut
        )
        currentEvent?.expenses.append(expense)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func removeExpense(_ expense: Expense) {
        guard currentEvent != nil else { return }
        
        currentEvent?.expenses.removeAll { $0.id == expense.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func addContributor(to expense: Expense, name: String, amount: Double) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        let contributor = Contributor(name: name, amount: amount)
        currentEvent?.expenses[index].contributors.append(contributor)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func removeContributor(from expense: Expense, contributor: Contributor) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        currentEvent?.expenses[index].contributors.removeAll { $0.id == contributor.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    // MARK: - Donation Management
    
    func addDonation(amount: Double, notes: String) {
        guard currentEvent != nil else { return }
        
        let donation = Donation(amount: amount, notes: notes)
        currentEvent?.donations.append(donation)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func removeDonation(_ donation: Donation) {
        guard currentEvent != nil else { return }
        
        currentEvent?.donations.removeAll { $0.id == donation.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    // MARK: - Balance Calculations
    
    func balance(for memberName: String) -> Double {
        guard let event = currentEvent else { return 0 }
        
        let totalPaid = event.expenses
            .filter { $0.paidBy == memberName && !$0.optOut }
            .reduce(0) { $0 + $1.amount }
        
        let totalContributed = event.expenses.reduce(0) { sum, expense in
            let contribution = expense.contributors.first { $0.name == memberName }
            return sum + (contribution?.amount ?? 0)
        }
        
        let totalReceived = event.expenses
            .filter { $0.paidBy == memberName }
            .reduce(0) { sum, expense in
                sum + expense.contributors.reduce(0) { $0 + $1.amount }
            }
        
        let isContributor = event.contributingMembers.contains { $0.name == memberName }
        let share = isContributor ? event.sharePerPerson : 0
        
        let result = totalPaid - totalReceived + totalContributed - share
        return result.isFinite ? result : 0
    }
    
    // MARK: - Data Persistence
    
    private func saveData() {
        // Save current event
        if let event = currentEvent,
           let encoded = try? JSONEncoder().encode(event) {
            UserDefaults.standard.set(encoded, forKey: eventKey)
        } else {
            UserDefaults.standard.removeObject(forKey: eventKey)
        }
        
        // Save events list (Pro users only)
        if isPro {
            if let encoded = try? JSONEncoder().encode(events) {
                UserDefaults.standard.set(encoded, forKey: eventsKey)
            }
        }
        
        // Save pro status
        UserDefaults.standard.set(isPro, forKey: proKey)
        
        // Force synchronize to ensure data is persisted
        UserDefaults.standard.synchronize()
    }
    
    private func loadData() {
        // Load pro status
        isPro = UserDefaults.standard.bool(forKey: proKey)
        
        // Load events list for Pro users
        if isPro {
            if let eventsData = UserDefaults.standard.data(forKey: eventsKey),
               let loadedEvents = try? JSONDecoder().decode([Event].self, from: eventsData) {
                events = loadedEvents
            }
        }
        
        // Try to load current event data
        if let eventData = UserDefaults.standard.data(forKey: eventKey),
           let event = try? JSONDecoder().decode(Event.self, from: eventData) {
            currentEvent = event
            
            // For Pro users, add to events list if not already there
            if isPro && !events.contains(where: { $0.id == event.id }) {
                events.append(event)
            }
            
            hasUnsavedChanges = false
            return
        }
        
        // If Pro user has events but no current event, select first
        if isPro && !events.isEmpty && currentEvent == nil {
            currentEvent = events.first
        }
        
        // Migrate from old format if exists
        migrateFromOldFormat()
    }
    
    private func migrateFromOldFormat() {
        let oldKey = "TheEqualizerData"
        guard let data = UserDefaults.standard.data(forKey: oldKey),
              let decoded = try? JSONDecoder().decode(SaveData.self, from: data) else {
            return
        }
        
        // Create event from old data
        currentEvent = Event(
            name: "My Event",
            members: decoded.members,
            expenses: decoded.expenses,
            donations: decoded.donations
        )
        
        // Save in new format
        saveData()
        
        // Remove old data
        UserDefaults.standard.removeObject(forKey: oldKey)
    }
    
    func clearAllData() {
        print("DEBUG: Clearing all data...")
        
        // Reset all state variables
        currentEvent = nil
        events = []
        hasUnsavedChanges = false
        isPro = false
        isFirebaseConnected = false
        isSyncing = false
        syncError = nil
        
        // Clear all UserDefaults keys
        UserDefaults.standard.removeObject(forKey: eventKey)
        UserDefaults.standard.removeObject(forKey: eventsKey)
        UserDefaults.standard.removeObject(forKey: proKey)
        
        // Force synchronize to ensure data is cleared
        UserDefaults.standard.synchronize()
        
        // Reset subscription manager if available
        if let manager = subscriptionManager {
            Task { @MainActor in
                manager.isProUser = false
                manager.subscriptionStatus = .notSubscribed
                manager.currentSubscription = nil
                
                // Force UI refresh after state update
                NotificationCenter.default.post(name: Notification.Name("ForceUIRefresh"), object: nil)
            }
        }
        
        print("DEBUG: All data cleared")
    }
    
    // MARK: - Navigation Health Check
    func performNavigationHealthCheck() -> Bool {
        var issues: [String] = []
        
        // Check if we have an event but no members (only warn, not fail - members can be added after event creation)
        if currentEvent != nil && members.isEmpty {
            print("INFO: Event exists but no members defined yet (normal for new events)")
        }
        
        // Check for proper navigation state consistency - Pro users should generally have events available
        if currentEvent == nil && isPro && events.isEmpty {
            issues.append("Pro user without any events available")
        }
        
        // Check state transition guards
        if hasUnsavedChanges && currentEvent == nil {
            issues.append("Unsaved changes flag set but no current event")
        }
        
        // Check free user constraints
        if !isPro && events.count > 1 {
            issues.append("Free user has multiple events (should only have currentEvent)")
        }
        
        if !issues.isEmpty {
            print("NAVIGATION HEALTH CHECK FAILED:")
            for issue in issues {
                print("  - \(issue)")
            }
            return false
        }
        
        print("NAVIGATION HEALTH CHECK PASSED")
        return true
    }
    
    func resetToFreeUser() {
        print("DEBUG: Resetting to free user...")
        
        // Reset to free user state
        isPro = false
        
        // Clear Pro features but keep current event
        events = []
        isFirebaseConnected = false
        
        // Ensure currentEvent is valid for free tier
        if let event = currentEvent {
            // Remove from events list if it exists
            events.removeAll { $0.id == event.id }
            
            // Update modification date
            currentEvent?.lastModified = Date()
        }
        
        // Clear Pro status from UserDefaults
        UserDefaults.standard.set(false, forKey: proKey)
        UserDefaults.standard.removeObject(forKey: eventsKey)
        
        // Force synchronize
        UserDefaults.standard.synchronize()
        
        // Update subscription manager and force UI refresh
        if let manager = subscriptionManager {
            Task { @MainActor in
                manager.isProUser = false
                manager.subscriptionStatus = .notSubscribed
                manager.currentSubscription = nil
                
                // Force UI refresh after state update
                NotificationCenter.default.post(name: Notification.Name("ForceUIRefresh"), object: nil)
            }
        }
        
        // Save the current event state
        saveData()
        
        print("DEBUG: Reset to free user completed")
    }
    
    // MARK: - Diagnostics
    
    @MainActor
    func printDiagnostics() {
        print("\n=== DataStore Diagnostics ===")
        print("isPro: \(isPro)")
        print("currentEvent: \(currentEvent?.name ?? "nil")")
        print("events count: \(events.count)")
        print("hasUnsavedChanges: \(hasUnsavedChanges)")
        print("isFirebaseConnected: \(isFirebaseConnected)")
        print("isSyncing: \(isSyncing)")
        
        if let manager = subscriptionManager {
            print("\nSubscriptionManager state:")
            print("  isProUser: \(manager.isProUser)")
            print("  subscriptionStatus: \(manager.subscriptionStatus)")
            print("  currentSubscription: \(manager.currentSubscription ?? "none")")
        }
        
        print("\nUserDefaults state:")
        print("  eventKey has data: \(UserDefaults.standard.data(forKey: eventKey) != nil)")
        print("  eventsKey has data: \(UserDefaults.standard.data(forKey: eventsKey) != nil)")
        print("  proKey value: \(UserDefaults.standard.bool(forKey: proKey))")
        
        print("\nData consistency check:")
        let isConsistent = (isPro == (subscriptionManager?.isProUser ?? false))
        print("  DataStore.isPro matches SubscriptionManager: \(isConsistent)")
        
        if !isPro && !events.isEmpty {
            print("  ⚠️ WARNING: Free user but has events in array!")
        }
        
        if currentEvent == nil && members.count > 0 {
            print("  ⚠️ WARNING: No current event but has members!")
        }
        
        print("===========================\n")
    }
    
    // MARK: - Migration & Repair
    
    func repairMissingEvents() {
        // Check if we have a current event that's not in the events list
        if let current = currentEvent, isPro {
            if !events.contains(where: { $0.id == current.id }) {
                events.append(current)
                saveData()
            }
        }
        
        // Try to recover any lost events from UserDefaults
        if isPro {
            // Check if there's event data that wasn't migrated
            if let eventData = UserDefaults.standard.data(forKey: eventKey),
               let event = try? JSONDecoder().decode(Event.self, from: eventData) {
                if !events.contains(where: { $0.id == event.id }) {
                    events.append(event)
                }
                if currentEvent == nil {
                    currentEvent = event
                }
                saveData()
            }
        }
    }
    
    // MARK: - Export/Import
    
    func exportData() -> String? {
        guard let event = currentEvent else { return nil }
        
        guard let encoded = try? JSONEncoder().encode(event),
              let jsonString = String(data: encoded, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    func importData(from jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data) else {
            return false
        }
        
        currentEvent = event
        hasUnsavedChanges = false
        saveData()
        return true
    }
}

// MARK: - Legacy Save Data Structure (for migration)

private struct SaveData: Codable {
    let members: [Member]
    let expenses: [Expense]
    let donations: [Donation]
    let savedAt: Date
    let version: String
}
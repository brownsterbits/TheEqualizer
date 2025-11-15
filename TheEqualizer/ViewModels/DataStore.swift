import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
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
    private var authStateListener: AuthStateDidChangeListenerHandle?
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
        // Ensure current event is preserved in events list
        if let current = currentEvent {
            if !events.contains(where: { $0.id == current.id }) {
                events.append(current)
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
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isFirebaseConnected = user != nil
                if user != nil {
                    // Sync for Pro users or if we have a shared event
                    if self?.isPro == true {
                        await self?.syncWithFirebase()
                    } else if let currentEvent = self?.currentEvent, 
                             currentEvent.firebaseId != nil {
                        // Non-Pro user with a shared event - set up listener
                        self?.setupEventListener(firebaseId: currentEvent.firebaseId!)
                    }
                }
            }
        }
    }
    
    deinit {
        // Clean up listeners
        eventListener?.remove()
        if let authStateListener = authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
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
                }
            }
            
            // Upload local events that aren't in Firebase (in background)
            let eventsToUpload = self.events.filter { $0.firebaseId == nil }
            let firebaseService = self.firebaseService
            
            Task.detached {
                for localEvent in eventsToUpload {
                    do {
                        let firebaseId = try await firebaseService.createEvent(localEvent)

                        // Update local event with Firebase ID on main thread
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
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
            
            // Remove any duplicates before updating (cleanup for existing bug)
            var cleanedEvents: [Event] = []
            var seenIds = Set<UUID>()
            
            for event in mergedEvents {
                if !seenIds.contains(event.id) {
                    cleanedEvents.append(event)
                    seenIds.insert(event.id)
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
        
        // Setup new listener for real-time collaboration
        eventListener = firebaseService.listenToEvent(eventId: firebaseId) { [weak self] event in
            guard let self = self, var event = event else { return }
            
            // Ensure UI updates happen on main thread
            Task { @MainActor in
                // Check if this is actually a different version
                if let currentEvent = self.currentEvent,
                   currentEvent.firebaseId == firebaseId {
                    
                    // Compare the actual content to see if it's different
                    let currentExpenseCount = currentEvent.expenses.count
                    let newExpenseCount = event.expenses.count
                    let currentMemberCount = currentEvent.members.count
                    let newMemberCount = event.members.count
                    let currentDonationCount = currentEvent.donations.count
                    let newDonationCount = event.donations.count
                    
                    // Check if the content is actually different
                    let hasChanges = currentExpenseCount != newExpenseCount || 
                                   currentMemberCount != newMemberCount ||
                                   currentDonationCount != newDonationCount ||
                                   currentEvent.name != event.name
                    
                    if !hasChanges {
                        // No actual changes, skip update
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
              let event = currentEvent else { return }
        
        // Allow sync for Pro users OR if the event has a Firebase ID (shared event)
        guard isPro || event.firebaseId != nil else { return }
        
        // Save in background - don't block UI
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                
                if let firebaseId = event.firebaseId {
                    // Update existing event
                    try await self.firebaseService.updateEvent(event, eventId: firebaseId)
                } else {
                    // Create new event
                    let firebaseId = try await self.firebaseService.createEvent(event)
                    
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
                }
            } catch {
                await MainActor.run {
                    self.syncError = error.localizedDescription
                }
                print("Error saving to Firebase: \(error)")
                // Don't fail - data is still saved locally
            }
        }
    }
    
    // MARK: - Manual Refresh
    
    @MainActor
    func refreshCurrentEvent() async {
        guard let event = currentEvent,
              let firebaseId = event.firebaseId,
              firebaseService.isAuthenticated else { return }
        
        do {
            // Fetch the latest version from Firebase
            if let updatedEvent = try await firebaseService.fetchEvent(eventId: firebaseId) {
                // Update current event with fresh data
                currentEvent = updatedEvent
                
                // Update in events list
                if let index = events.firstIndex(where: { $0.firebaseId == firebaseId }) {
                    events[index] = updatedEvent
                }
                
                // Save locally
                saveData()
                
                // Ensure listener is active
                setupEventListener(firebaseId: firebaseId)
            }
        } catch {
            syncError = "Failed to refresh. Pull down to try again."
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
    
    var totalExpenses: Decimal {
        currentEvent?.totalExpenses ?? 0
    }
    
    var reimbursableExpenses: Decimal {
        currentEvent?.reimbursableExpenses ?? 0
    }
    
    var totalDonations: Decimal {
        currentEvent?.totalDonations ?? 0
    }
    
    var directContributions: Decimal {
        currentEvent?.directContributions ?? 0
    }
    
    var sharePerPerson: Decimal {
        currentEvent?.sharePerPerson ?? 0
    }
    
    // MARK: - Event Management
    
    func createEvent(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        let newEvent = Event(name: trimmedName)
        
        if isPro {
            events.append(newEvent)
            currentEvent = newEvent
        } else {
            // Free users: replace their single event
            currentEvent = newEvent
            events = [newEvent]
        }
        
        hasUnsavedChanges = true
        saveData()
        
        // Sync to Firebase if authenticated
        if firebaseService.isAuthenticated && isPro {
            saveToFirebase()
        }
    }
    
    func selectEvent(_ event: Event) {
        // State transition guard: Only Pro users can select events
        guard isPro else {
            return
        }
        
        currentEvent = event
        currentEventFirebaseId = event.firebaseId
        
        // Setup real-time listener if event has Firebase ID
        if let firebaseId = event.firebaseId {
            setupEventListener(firebaseId: firebaseId)
        }
        
        saveData()
    }
    
    func deleteEvent(_ event: Event) {
        // Remove listener if this is the current event
        if currentEvent?.id == event.id {
            eventListener?.remove()
            eventListener = nil
        }
        
        // Remove from arrays
        events.removeAll { $0.id == event.id }
        
        // Update current event
        if currentEvent?.id == event.id {
            currentEvent = isPro ? events.first : nil
        }
        
        // Save locally
        saveData()
        
        // Delete from Firebase if needed
        if let firebaseId = event.firebaseId, firebaseService.isAuthenticated {
            Task {
                do {
                    try await firebaseService.deleteEvent(eventId: firebaseId)
                } catch {
                    // If permission denied, show error but keep local delete
                    // (user can't delete shared events they don't own)
                    if error.localizedDescription.lowercased().contains("permission") {
                        await MainActor.run {
                            self.syncError = "Only the event creator can delete this shared event"
                        }
                    }
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
        // First ensure we're authenticated
        if !firebaseService.isAuthenticated {
            do {
                try await firebaseService.signInAnonymously()
                // Wait a moment for auth to stabilize
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } catch {
                syncError = "Failed to connect. Please check your internet connection."
                return nil
            }
        }
        
        // If event doesn't have a Firebase ID, we need to upload it first
        var eventFirebaseId = event.firebaseId
        if eventFirebaseId == nil {
            isSyncing = true
            do {
                eventFirebaseId = try await firebaseService.createEvent(event)
                
                // Update local event with Firebase ID
                await MainActor.run {
                    if let index = self.events.firstIndex(where: { $0.id == event.id }) {
                        self.events[index].firebaseId = eventFirebaseId
                    }
                    if self.currentEvent?.id == event.id {
                        self.currentEvent?.firebaseId = eventFirebaseId
                    }
                    self.saveData()
                }
                
                // Setup real-time listener for this event
                if let firebaseId = eventFirebaseId {
                    setupEventListener(firebaseId: firebaseId)
                }
            } catch {
                isSyncing = false
                syncError = "Failed to prepare event for sharing. Please try again."
                return nil
            }
            isSyncing = false
        }

        guard let firebaseId = eventFirebaseId else {
            syncError = "Failed to prepare event for sharing."
            return nil
        }
        
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
            syncError = "Failed to generate invite code. Please try again."
            return nil
        }
    }
    
    @MainActor
    func handleInviteCode(_ code: String) async -> Bool {
        // First ensure we're authenticated (even non-Pro users need auth for shared events)
        if !firebaseService.isAuthenticated {
            do {
                try await firebaseService.signInAnonymously()
                // Wait a moment for auth to stabilize
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } catch {
                syncError = "Failed to connect. Please check your internet connection."
                return false
            }
        }

        do {
            let eventId = try await firebaseService.joinEventWithCode(code)
            
            // For shared events, allow sync even for non-Pro users
            if isPro {
                // Pro users get full sync
                await syncWithFirebase()
            } else {
                // Non-Pro users can join one shared event
                await syncSharedEvent(firebaseEventId: eventId)
            }
            return true
        } catch {
            print("Error joining event with code: \(error)")
            if error.localizedDescription.contains("invalid") || error.localizedDescription.contains("Invalid") {
                syncError = "Invalid invite code. Please check and try again."
            } else {
                syncError = "Failed to join event. Please try again."
            }
            return false
        }
    }
    
    @MainActor
    private func syncSharedEvent(firebaseEventId: String) async {
        guard firebaseService.isAuthenticated else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Fetch the specific shared event
            let event = try await firebaseService.fetchEvent(eventId: firebaseEventId)

            if let event = event {
                // For non-Pro users, replace their single event with the shared one
                if !isPro {
                    currentEvent = event
                    events = [event]
                } else {
                    // Pro users add to their events list
                    if !events.contains(where: { $0.firebaseId == firebaseEventId }) {
                        events.append(event)
                        currentEvent = event
                    }
                }
                
                // Setup real-time listener for this shared event
                setupEventListener(firebaseId: firebaseEventId)

                // Save locally
                saveData()
            }
            
            isSyncing = false
        } catch {
            syncError = "Failed to load shared event. Please try again."
            isSyncing = false
        }
    }
    
    func renameCurrentEvent(to newName: String) {
        currentEvent?.name = newName
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
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
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Save locally immediately - this ensures UI persistence
        saveData()
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
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
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
            saveToFirebase()
        }
    }
    
    func memberExists(name: String) -> Bool {
        currentEvent?.members.contains { $0.name == name } ?? false
    }
    
    // MARK: - Expense Management
    
    func addExpense(description: String, amount: Decimal, paidBy: String, notes: String, optOut: Bool) {
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
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Save locally immediately
        saveData()
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
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
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
            saveToFirebase()
        }
    }
    
    func addContributor(to expense: Expense, name: String, amount: Decimal) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        let contributor = Contributor(name: name, amount: amount)
        currentEvent?.expenses[index].contributors.append(contributor)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
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
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
            saveToFirebase()
        }
    }
    
    // MARK: - Donation Management
    
    func addDonation(amount: Decimal, notes: String) {
        guard currentEvent != nil else { return }
        
        let donation = Donation(amount: amount, notes: notes)
        currentEvent?.donations.append(donation)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        
        // Save locally immediately
        saveData()
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
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
        
        // Trigger SwiftUI update by reassigning currentEvent
        if let event = currentEvent {
            currentEvent = event
        }
        
        // Sync to Firebase in background if authenticated and (Pro or shared event)
        if firebaseService.isAuthenticated && (isPro || currentEvent?.firebaseId != nil) {
            saveToFirebase()
        }
    }
    
    // MARK: - Balance Calculations
    
    func balance(for memberName: String) -> Decimal {
        guard let event = currentEvent else { return 0 }
        
        let totalPaid = event.expenses
            .filter { $0.paidBy == memberName && !$0.optOut }
            .reduce(0) { $0 + $1.amount }
        
        let totalContributed = event.expenses.reduce(Decimal(0)) { sum, expense in
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
        
        return totalPaid - totalReceived + totalContributed - share
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

        // Note: synchronize() is deprecated and unnecessary - iOS handles persistence automatically
    }
    
    private func loadData() {
        // Load pro status
        isPro = UserDefaults.standard.bool(forKey: proKey)
        
        // Load events list for Pro users
        if isPro {
            if let eventsData = UserDefaults.standard.data(forKey: eventsKey),
               let loadedEvents = try? JSONDecoder().decode([Event].self, from: eventsData) {
                events = loadedEvents
                
                // If we have events but no current event, select the first one
                if currentEvent == nil && !events.isEmpty {
                    currentEvent = events.first
                }
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
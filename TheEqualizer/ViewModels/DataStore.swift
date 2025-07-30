import Foundation
import SwiftUI
import CloudKit

class DataStore: ObservableObject {
    @Published var currentEvent: Event?
    @Published var events: [Event] = []
    @Published var hasUnsavedChanges = false
    @Published var isPro = false
    @Published var isCloudKitEnabled = false
    @Published var cloudKitStatus: CKAccountStatus = .couldNotDetermine
    
    let cloudKitService: CloudKitService
    
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
        
        // Check CloudKit status now that user is Pro
        Task {
            await checkCloudKitStatus()
        }
    }
    
    private func handleProDowngrade() {
        print("DEBUG: User downgraded from Pro")
        
        // Disable CloudKit
        isCloudKitEnabled = false
        cloudKitStatus = .couldNotDetermine
        
        // Clear events list but keep current event
        events = []
        
        saveData()
    }
    
    private let eventKey = "TheEqualizerEvent"
    private let eventsKey = "TheEqualizerEvents"
    private let proKey = "TheEqualizerProStatus"
    
    init() {
        cloudKitService = CloudKitService()
        loadData()
        
        // Debug: Try to repair missing events on init
        if isPro {
            repairMissingEvents()
        }
        
        Task {
            await checkCloudKitStatus()
        }
    }
    
    // MARK: - CloudKit Status
    
    @MainActor
    func checkCloudKitStatus() async {
        cloudKitStatus = await cloudKitService.checkAccountStatus()
        isCloudKitEnabled = (cloudKitStatus == .available) && isPro
        
        print("DEBUG: CloudKit status check - Status: \(cloudKitStatus), isPro: \(isPro), enabled: \(isCloudKitEnabled)")
        
        if isCloudKitEnabled {
            print("DEBUG: Starting CloudKit sync...")
            await syncWithCloudKit()
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
    
    // MARK: - CloudKit Sync
    
    @MainActor
    private func syncWithCloudKit() async {
        guard isCloudKitEnabled else { return }
        
        do {
            // Fetch both private and shared events from CloudKit
            let privateEvents = try await cloudKitService.fetchEvents()
            let sharedEvents = try await cloudKitService.fetchSharedEvents()
            let cloudEvents = privateEvents + sharedEvents
            
            print("DEBUG: Fetched \(privateEvents.count) private events and \(sharedEvents.count) shared events from CloudKit")
            print("DEBUG: Local events count: \(events.count)")
            
            // Merge strategy: keep local events and add any new cloud events
            var mergedEvents = events
            
            for cloudEvent in cloudEvents {
                if !mergedEvents.contains(where: { $0.id == cloudEvent.id }) {
                    mergedEvents.append(cloudEvent)
                }
            }
            
            // If we have local events that aren't in CloudKit, upload them
            for localEvent in events {
                if !cloudEvents.contains(where: { $0.id == localEvent.id }) {
                    do {
                        let _ = try await cloudKitService.saveEvent(localEvent)
                        // Also save all related data
                        let _ = try await cloudKitService.saveMembers(localEvent.members, eventID: localEvent.id)
                        let _ = try await cloudKitService.saveExpenses(localEvent.expenses, eventID: localEvent.id)
                        let _ = try await cloudKitService.saveDonations(localEvent.donations, eventID: localEvent.id)
                    } catch {
                        print("Error uploading local event to CloudKit: \(error)")
                    }
                }
            }
            
            // Update events list with merged results
            self.events = mergedEvents
            
            // If no current event, set to first available
            if currentEvent == nil && !events.isEmpty {
                currentEvent = events.first
                await loadEventData(events.first!)
            }
            
            hasUnsavedChanges = false
        } catch {
            print("Error syncing with CloudKit: \(error)")
        }
    }
    
    @MainActor
    private func loadEventData(_ event: Event) async {
        guard isCloudKitEnabled else { return }
        
        do {
            // Load all related data for the event
            let members = try await cloudKitService.fetchMembers(for: event.id)
            let expenses = try await cloudKitService.fetchExpenses(for: event.id)
            let donations = try await cloudKitService.fetchDonations(for: event.id)
            
            // Update current event with loaded data
            currentEvent?.members = members
            currentEvent?.expenses = expenses
            currentEvent?.donations = donations
        } catch {
            print("Error loading event data: \(error)")
        }
    }
    
    private func saveToCloudKit() {
        guard isCloudKitEnabled, let event = currentEvent else { return }
        
        Task {
            do {
                // Save event
                let savedEvent = try await cloudKitService.saveEvent(event)
                
                // Save related data
                let _ = try await cloudKitService.saveMembers(event.members, eventID: event.id)
                let _ = try await cloudKitService.saveExpenses(event.expenses, eventID: event.id)
                let _ = try await cloudKitService.saveDonations(event.donations, eventID: event.id)
                
                await MainActor.run {
                    // Update events list
                    if let index = events.firstIndex(where: { $0.id == savedEvent.id }) {
                        events[index] = savedEvent
                    } else {
                        events.append(savedEvent)
                    }
                    hasUnsavedChanges = false
                }
            } catch {
                print("Error saving to CloudKit: \(error)")
            }
        }
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
        saveData()
        
        // Trigger navigation health check after state change
        let _ = performNavigationHealthCheck()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    func selectEvent(_ event: Event) {
        // State transition guard: Only Pro users can select events
        guard isPro else { 
            print("WARNING: Free user attempting to select event")
            return 
        }
        
        currentEvent = event
        
        // Trigger navigation health check after state change
        let _ = performNavigationHealthCheck()
        
        if isCloudKitEnabled {
            Task {
                await loadEventData(event)
            }
        }
        
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
        
        // Remove from local arrays (Pro users only)
        if isPro {
            events.removeAll { $0.id == event.id }
        }
        
        // Clear current event if it's the one being deleted
        if currentEvent?.id == event.id {
            if isPro {
                currentEvent = events.first
            } else {
                // Free user - clear current event completely
                currentEvent = nil
            }
        }
        
        // Trigger navigation health check after state change
        let _ = performNavigationHealthCheck()
        
        // Delete from CloudKit
        if isCloudKitEnabled {
            Task {
                try? await cloudKitService.deleteEvent(event)
            }
        }
        
        saveData()
    }
    
    func deleteCurrentEvent() {
        guard let event = currentEvent else { return }
        deleteEvent(event)
    }
    
    @MainActor
    func shareEvent(_ event: Event) async -> CKShare? {
        guard isCloudKitEnabled else { return nil }
        
        do {
            let share = try await cloudKitService.shareEvent(event)
            
            // Update the event's shared status
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index].isShared = true
            }
            if currentEvent?.id == event.id {
                currentEvent?.isShared = true
            }
            
            saveData()
            return share
        } catch {
            print("Error sharing event: \(error)")
            return nil
        }
    }
    
    func renameCurrentEvent(to newName: String) {
        currentEvent?.name = newName
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    // MARK: - Member Management
    
    func addMember(name: String, type: MemberType) {
        guard currentEvent != nil else { return }
        
        let member = Member(name: name, type: type)
        currentEvent?.members.append(member)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
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
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
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
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    func removeExpense(_ expense: Expense) {
        guard currentEvent != nil else { return }
        
        currentEvent?.expenses.removeAll { $0.id == expense.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    func addContributor(to expense: Expense, name: String, amount: Double) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        let contributor = Contributor(name: name, amount: amount)
        currentEvent?.expenses[index].contributors.append(contributor)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    func removeContributor(from expense: Expense, contributor: Contributor) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        currentEvent?.expenses[index].contributors.removeAll { $0.id == contributor.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    // MARK: - Donation Management
    
    func addDonation(amount: Double, notes: String) {
        guard currentEvent != nil else { return }
        
        let donation = Donation(amount: amount, notes: notes)
        currentEvent?.donations.append(donation)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
        }
    }
    
    func removeDonation(_ donation: Donation) {
        guard currentEvent != nil else { return }
        
        currentEvent?.donations.removeAll { $0.id == donation.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
        
        if isCloudKitEnabled {
            saveToCloudKit()
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
        isCloudKitEnabled = false
        cloudKitStatus = .couldNotDetermine
        
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
        isCloudKitEnabled = false
        cloudKitStatus = .couldNotDetermine
        
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
        print("isCloudKitEnabled: \(isCloudKitEnabled)")
        print("cloudKitStatus: \(cloudKitStatus)")
        
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
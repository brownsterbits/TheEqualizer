import Foundation
import SwiftUI

class DataStore: ObservableObject {
    @Published var currentEvent: Event?
    @Published var hasUnsavedChanges = false
    @Published var isPro = false // Will be tied to subscription later
    
    weak var subscriptionManager: SubscriptionManager? {
        didSet {
            // Sync Pro status when subscription manager is set
            Task { @MainActor in
                if let manager = subscriptionManager {
                    isPro = manager.isProUser
                    
                    // Listen for subscription changes
                    manager.$isProUser
                        .assign(to: &$isPro)
                }
            }
        }
    }
    
    private let eventKey = "TheEqualizerEvent"
    private let proKey = "TheEqualizerProStatus"
    
    init() {
        loadData()
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
        // Free users can only have one event
        if !isPro && currentEvent != nil {
            return
        }
        
        currentEvent = Event(name: name)
        hasUnsavedChanges = true
        saveData()
    }
    
    func deleteCurrentEvent() {
        currentEvent = nil
        hasUnsavedChanges = false
        saveData()
    }
    
    func renameCurrentEvent(to newName: String) {
        currentEvent?.name = newName
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
    }
    
    // MARK: - Member Management
    
    func addMember(name: String, type: MemberType) {
        guard currentEvent != nil else { return }
        
        let member = Member(name: name, type: type)
        currentEvent?.members.append(member)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
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
    }
    
    func removeExpense(_ expense: Expense) {
        guard currentEvent != nil else { return }
        
        currentEvent?.expenses.removeAll { $0.id == expense.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
    }
    
    func addContributor(to expense: Expense, name: String, amount: Double) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        let contributor = Contributor(name: name, amount: amount)
        currentEvent?.expenses[index].contributors.append(contributor)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
    }
    
    func removeContributor(from expense: Expense, contributor: Contributor) {
        guard let eventExpenses = currentEvent?.expenses,
              let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        
        currentEvent?.expenses[index].contributors.removeAll { $0.id == contributor.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
    }
    
    // MARK: - Donation Management
    
    func addDonation(amount: Double, notes: String) {
        guard currentEvent != nil else { return }
        
        let donation = Donation(amount: amount, notes: notes)
        currentEvent?.donations.append(donation)
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
    }
    
    func removeDonation(_ donation: Donation) {
        guard currentEvent != nil else { return }
        
        currentEvent?.donations.removeAll { $0.id == donation.id }
        currentEvent?.lastModified = Date()
        hasUnsavedChanges = true
        saveData()
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
        // Save event
        if let event = currentEvent,
           let encoded = try? JSONEncoder().encode(event) {
            UserDefaults.standard.set(encoded, forKey: eventKey)
        } else {
            UserDefaults.standard.removeObject(forKey: eventKey)
        }
        
        // Save pro status
        UserDefaults.standard.set(isPro, forKey: proKey)
    }
    
    private func loadData() {
        // Load pro status
        isPro = UserDefaults.standard.bool(forKey: proKey)
        
        // Try to load event data first
        if let eventData = UserDefaults.standard.data(forKey: eventKey),
           let event = try? JSONDecoder().decode(Event.self, from: eventData) {
            currentEvent = event
            hasUnsavedChanges = false
            return
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
        currentEvent = nil
        hasUnsavedChanges = false
        saveData()
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
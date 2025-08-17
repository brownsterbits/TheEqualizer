import Foundation

struct Event: Identifiable, Codable, Equatable {
    var id: UUID  // Changed from let to var to allow UUID preservation during sync
    var name: String
    var members: [Member]
    var expenses: [Expense]
    var donations: [Donation]
    let createdAt: Date
    var lastModified: Date
    
    // Firebase properties
    var firebaseId: String?
    var createdBy: String?
    var collaborators: [String: Bool] = [:]
    var inviteCode: String?
    
    init(id: UUID = UUID(),
         name: String,
         members: [Member] = [],
         expenses: [Expense] = [],
         donations: [Donation] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.members = members
        self.expenses = expenses
        self.donations = donations
        self.createdAt = createdAt
        self.lastModified = createdAt
    }
    
    // Computed properties (moved from DataStore)
    var contributingMembers: [Member] {
        members.filter { $0.type == .contributing }
    }
    
    var reimbursementMembers: [Member] {
        members.filter { $0.type == .reimbursementOnly }
    }
    
    var totalExpenses: Double {
        let result = expenses.reduce(0) { $0 + $1.amount }
        return result.isFinite ? result : 0
    }
    
    var reimbursableExpenses: Double {
        let result = expenses.filter { !$0.optOut }.reduce(0) { $0 + $1.amount }
        return result.isFinite ? result : 0
    }
    
    var totalDonations: Double {
        let result = donations.reduce(0) { $0 + $1.amount }
        return result.isFinite ? result : 0
    }
    
    var directContributions: Double {
        let result = expenses.reduce(0) { sum, expense in
            sum + expense.contributors.reduce(0) { $0 + $1.amount }
        }
        return result.isFinite ? result : 0
    }
    
    var amountToShare: Double {
        let result = reimbursableExpenses - totalDonations
        return result.isFinite ? result : 0
    }
    
    var sharePerPerson: Double {
        let count = contributingMembers.count
        guard count > 0, amountToShare.isFinite else { return 0 }
        let result = amountToShare / Double(count)
        return result.isFinite ? result : 0
    }
}
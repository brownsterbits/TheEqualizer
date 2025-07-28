import Foundation

struct Event: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var members: [Member]
    var expenses: [Expense]
    var donations: [Donation]
    let createdAt: Date
    var lastModified: Date
    
    // For future CloudKit sync
    var isShared: Bool = false
    var ownerID: String? = nil
    
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
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    var reimbursableExpenses: Double {
        expenses.filter { !$0.optOut }.reduce(0) { $0 + $1.amount }
    }
    
    var totalDonations: Double {
        donations.reduce(0) { $0 + $1.amount }
    }
    
    var directContributions: Double {
        expenses.reduce(0) { sum, expense in
            sum + expense.contributors.reduce(0) { $0 + $1.amount }
        }
    }
    
    var amountToShare: Double {
        reimbursableExpenses - totalDonations
    }
    
    var sharePerPerson: Double {
        contributingMembers.isEmpty ? 0 : amountToShare / Double(contributingMembers.count)
    }
}
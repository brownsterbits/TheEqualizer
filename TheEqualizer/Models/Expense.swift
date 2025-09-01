import Foundation

struct Contributor: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let amount: Decimal
    
    init(id: UUID = UUID(), name: String, amount: Decimal) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

struct Expense: Identifiable, Codable, Equatable {
    let id: UUID
    var description: String
    var amount: Decimal
    var paidBy: String
    var notes: String
    var optOut: Bool
    var contributors: [Contributor]
    let date: Date
    
    init(id: UUID = UUID(), 
         description: String, 
         amount: Decimal, 
         paidBy: String, 
         notes: String = "", 
         optOut: Bool = false, 
         contributors: [Contributor] = [],
         date: Date = Date()) {
        self.id = id
        self.description = description
        self.amount = amount
        self.paidBy = paidBy
        self.notes = notes
        self.optOut = optOut
        self.contributors = contributors
        self.date = date
    }
    
    var totalContributions: Decimal {
        return contributors.reduce(0) { $0 + $1.amount }
    }
    
    var remainingAmount: Decimal {
        let result = amount - totalContributions
        return max(0, result)  // Ensure non-negative
    }
}
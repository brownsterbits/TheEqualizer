import Foundation

struct Contributor: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let amount: Double
    
    init(id: UUID = UUID(), name: String, amount: Double) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

struct Expense: Identifiable, Codable, Equatable {
    let id: UUID
    var description: String
    var amount: Double
    var paidBy: String
    var notes: String
    var optOut: Bool
    var contributors: [Contributor]
    let date: Date
    
    init(id: UUID = UUID(), 
         description: String, 
         amount: Double, 
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
    
    var totalContributions: Double {
        let result = contributors.reduce(0) { $0 + $1.amount }
        return result.isFinite ? result : 0
    }
    
    var remainingAmount: Double {
        let result = amount - totalContributions
        return result.isFinite ? max(0, result) : 0  // Also ensure non-negative
    }
}
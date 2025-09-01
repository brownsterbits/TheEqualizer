import Foundation

struct Donation: Identifiable, Codable, Equatable {
    let id: UUID
    var amount: Decimal
    var notes: String
    let date: Date
    
    init(id: UUID = UUID(), amount: Decimal, notes: String = "", date: Date = Date()) {
        self.id = id
        self.amount = amount
        self.notes = notes
        self.date = date
    }
}
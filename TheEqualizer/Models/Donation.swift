import Foundation

struct Donation: Identifiable, Codable, Equatable {
    let id: UUID
    var amount: Double
    var notes: String
    let date: Date
    
    init(id: UUID = UUID(), amount: Double, notes: String = "", date: Date = Date()) {
        self.id = id
        self.amount = amount
        self.notes = notes
        self.date = date
    }
}
import Foundation

enum MemberType: String, Codable, CaseIterable {
    case contributing = "contributing"
    case reimbursementOnly = "reimbursementOnly"
    
    var displayName: String {
        switch self {
        case .contributing:
            return "Contributing"
        case .reimbursementOnly:
            return "Reimbursement Only"
        }
    }
}

struct Member: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let type: MemberType
    
    init(id: UUID = UUID(), name: String, type: MemberType) {
        self.id = id
        self.name = name
        self.type = type
    }
}
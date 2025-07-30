import CloudKit
import Foundation

class CloudKitService: ObservableObject {
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    
    init() {
        container = CKContainer.default()
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
    }
    
    // MARK: - Account Status
    
    func checkAccountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            print("Error checking CloudKit account status: \(error)")
            return .couldNotDetermine
        }
    }
    
    // MARK: - Event Operations
    
    func saveEvent(_ event: Event) async throws -> Event {
        let record = CKRecord(event: event)
        do {
            let savedRecord = try await privateDatabase.save(record)
            return Event(from: savedRecord)
        } catch {
            print("Error saving event: \(error)")
            throw error
        }
    }
    
    func fetchEvents() async throws -> [Event] {
        let query = CKQuery(recordType: "Event", predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        var events: [Event] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                events.append(Event(from: record))
            case .failure(let error):
                print("Error fetching event: \(error)")
            }
        }
        return events.sorted { $0.lastModified > $1.lastModified }
    }
    
    func deleteEvent(_ event: Event) async throws {
        let recordID = CKRecord.ID(recordName: event.id.uuidString)
        try await privateDatabase.deleteRecord(withID: recordID)
    }
    
    // MARK: - Member Operations
    
    func saveMembers(_ members: [Member], eventID: UUID) async throws -> [Member] {
        var savedMembers: [Member] = []
        
        for member in members {
            do {
                let record = CKRecord(member: member, eventID: eventID)
                let savedRecord = try await privateDatabase.save(record)
                savedMembers.append(Member(from: savedRecord))
            } catch {
                print("Error saving member \(member.name): \(error)")
                throw error
            }
        }
        
        return savedMembers
    }
    
    func fetchMembers(for eventID: UUID) async throws -> [Member] {
        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Member", predicate: predicate)
        let results = try await privateDatabase.records(matching: query)
        
        var members: [Member] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                members.append(Member(from: record))
            case .failure(let error):
                print("Error fetching member: \(error)")
            }
        }
        return members
    }
    
    // MARK: - Expense Operations
    
    func saveExpenses(_ expenses: [Expense], eventID: UUID) async throws -> [Expense] {
        var savedExpenses: [Expense] = []
        
        for expense in expenses {
            do {
                let record = CKRecord(expense: expense, eventID: eventID)
                let savedRecord = try await privateDatabase.save(record)
                savedExpenses.append(Expense(from: savedRecord))
            } catch {
                print("Error saving expense \(expense.description): \(error)")
                throw error
            }
        }
        
        return savedExpenses
    }
    
    func fetchExpenses(for eventID: UUID) async throws -> [Expense] {
        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Expense", predicate: predicate)
        let results = try await privateDatabase.records(matching: query)
        
        var expenses: [Expense] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                expenses.append(Expense(from: record))
            case .failure(let error):
                print("Error fetching expense: \(error)")
            }
        }
        return expenses
    }
    
    // MARK: - Donation Operations
    
    func saveDonations(_ donations: [Donation], eventID: UUID) async throws -> [Donation] {
        var savedDonations: [Donation] = []
        
        for donation in donations {
            do {
                let record = CKRecord(donation: donation, eventID: eventID)
                let savedRecord = try await privateDatabase.save(record)
                savedDonations.append(Donation(from: savedRecord))
            } catch {
                print("Error saving donation: \(error)")
                throw error
            }
        }
        
        return savedDonations
    }
    
    func fetchDonations(for eventID: UUID) async throws -> [Donation] {
        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Donation", predicate: predicate)
        let results = try await privateDatabase.records(matching: query)
        
        var donations: [Donation] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                donations.append(Donation(from: record))
            case .failure(let error):
                print("Error fetching donation: \(error)")
            }
        }
        return donations
    }
    
    // MARK: - Sharing Operations
    
    func shareEvent(_ event: Event) async throws -> CKShare {
        let eventRecord = CKRecord(event: event)
        let share = CKShare(rootRecord: eventRecord)
        share[CKShare.SystemFieldKey.title] = event.name
        share.publicPermission = .none
        
        do {
            let modifyResult = try await privateDatabase.modifyRecords(saving: [eventRecord, share], deleting: [])
            
            // Extract the saved share from the results
            for (_, result) in modifyResult.saveResults {
                switch result {
                case .success(let savedRecord):
                    if let savedShare = savedRecord as? CKShare {
                        return savedShare
                    }
                case .failure(let error):
                    throw error
                }
            }
            
            throw CKError(.internalError)
        } catch {
            print("Error saving records: \(error)")
            throw error
        }
    }
    
    func fetchSharedEvents() async throws -> [Event] {
        let query = CKQuery(recordType: "Event", predicate: NSPredicate(value: true))
        let results = try await sharedDatabase.records(matching: query)
        
        var events: [Event] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                events.append(Event(from: record))
            case .failure(let error):
                print("Error fetching shared event: \(error)")
            }
        }
        return events.sorted { $0.lastModified > $1.lastModified }
    }
    
    func acceptSharedEvent(from metadata: CKShare.Metadata) async throws {
        let acceptOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        acceptOperation.perShareResultBlock = { (metadata: CKShare.Metadata, result: Result<CKShare, Error>) in
            switch result {
            case .success(let share):
                print("Successfully accepted shared event: \(share)")
            case .failure(let error):
                print("Error accepting share: \(error)")
            }
        }
        
        container.add(acceptOperation)
    }
}

// MARK: - CKRecord Extensions

extension CKRecord {
    convenience init(event: Event) {
        self.init(recordType: "Event", recordID: CKRecord.ID(recordName: event.id.uuidString))
        self["name"] = event.name
        self["createdAt"] = event.createdAt
        self["lastModified"] = event.lastModified
        self["isShared"] = event.isShared
        self["ownerID"] = event.ownerID
    }
    
    convenience init(member: Member, eventID: UUID) {
        self.init(recordType: "Member", recordID: CKRecord.ID(recordName: member.id.uuidString))
        self["name"] = member.name
        self["type"] = member.type.rawValue
        self["eventID"] = eventID.uuidString
    }
    
    convenience init(expense: Expense, eventID: UUID) {
        self.init(recordType: "Expense", recordID: CKRecord.ID(recordName: expense.id.uuidString))
        self["description"] = expense.description
        self["amount"] = expense.amount
        self["paidBy"] = expense.paidBy
        self["notes"] = expense.notes
        self["optOut"] = expense.optOut
        self["date"] = expense.date
        self["eventID"] = eventID.uuidString
        
        // Store contributors as JSON data
        if let contributorsData = try? JSONEncoder().encode(expense.contributors) {
            self["contributors"] = contributorsData
        }
    }
    
    convenience init(donation: Donation, eventID: UUID) {
        self.init(recordType: "Donation", recordID: CKRecord.ID(recordName: donation.id.uuidString))
        self["amount"] = donation.amount
        self["notes"] = donation.notes
        self["date"] = donation.date
        self["eventID"] = eventID.uuidString
    }
}

// MARK: - Model Extensions

extension Event {
    init(from record: CKRecord) {
        self.init(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            name: record["name"] as? String ?? "",
            members: [], // Will be loaded separately
            expenses: [], // Will be loaded separately
            donations: [], // Will be loaded separately
            createdAt: record["createdAt"] as? Date ?? Date()
        )
        self.lastModified = record["lastModified"] as? Date ?? Date()
        self.isShared = record["isShared"] as? Bool ?? false
        self.ownerID = record["ownerID"] as? String
    }
}

extension Member {
    init(from record: CKRecord) {
        self.init(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            name: record["name"] as? String ?? "",
            type: MemberType(rawValue: record["type"] as? String ?? "contributing") ?? .contributing
        )
    }
}

extension Expense {
    init(from record: CKRecord) {
        let contributors: [Contributor]
        if let contributorsData = record["contributors"] as? Data,
           let decodedContributors = try? JSONDecoder().decode([Contributor].self, from: contributorsData) {
            contributors = decodedContributors
        } else {
            contributors = []
        }
        
        self.init(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            description: record["description"] as? String ?? "",
            amount: record["amount"] as? Double ?? 0.0,
            paidBy: record["paidBy"] as? String ?? "",
            notes: record["notes"] as? String ?? "",
            optOut: record["optOut"] as? Bool ?? false,
            contributors: contributors,
            date: record["date"] as? Date ?? Date()
        )
    }
}

extension Donation {
    init(from record: CKRecord) {
        self.init(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            amount: record["amount"] as? Double ?? 0.0,
            notes: record["notes"] as? String ?? "",
            date: record["date"] as? Date ?? Date()
        )
    }
}
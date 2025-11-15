import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

class FirebaseService: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var authError: String?
    
    private let db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var eventListeners: [ListenerRegistration] = []
    
    init() {
        setupAuthListener()
    }
    
    deinit {
        authStateListener.map { Auth.auth().removeStateDidChangeListener($0) }
        eventListeners.forEach { $0.remove() }
    }
    
    // MARK: - Authentication
    
    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    func signInAnonymously() async throws {
        do {
            let result = try await Auth.auth().signInAnonymously()
            await MainActor.run {
                user = result.user
                isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
            throw error
        }
    }
    
    func signInWithApple(authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }
        
        guard let nonce = currentNonce else {
            throw AuthError.missingNonce
        }
        
        guard let appleIDToken = appleIDCredential.identityToken else {
            throw AuthError.missingToken
        }
        
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidToken
        }
        
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        
        do {
            let result = try await Auth.auth().signIn(with: credential)
            await MainActor.run {
                user = result.user
                isAuthenticated = true
            }
            
            // Update user profile in Firestore
            try await updateUserProfile(email: appleIDCredential.email)
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
            throw error
        }
    }
    
    func linkAnonymousToApple(authorization: ASAuthorization) async throws {
        guard let currentUser = Auth.auth().currentUser,
              currentUser.isAnonymous else {
            throw AuthError.notAnonymous
        }
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }
        
        guard let nonce = currentNonce else {
            throw AuthError.missingNonce
        }
        
        guard let appleIDToken = appleIDCredential.identityToken else {
            throw AuthError.missingToken
        }
        
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidToken
        }
        
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        
        do {
            let result = try await currentUser.link(with: credential)
            await MainActor.run {
                user = result.user
            }
            
            // Update user profile in Firestore
            try await updateUserProfile(email: appleIDCredential.email)
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
            throw error
        }
    }
    
    private func updateUserProfile(email: String?) async throws {
        guard let userId = user?.uid else { return }
        
        let userRef = db.collection("users").document(userId)
        try await userRef.setData([
            "email": email ?? "",
            // Note: isPro status should be managed server-side via receipt validation
            // Client-side status is handled by SubscriptionManager
            "createdAt": FieldValue.serverTimestamp(),
            "lastLogin": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        Task { @MainActor in
            user = nil
            isAuthenticated = false
        }
    }
    
    // MARK: - Apple Sign In Nonce
    
    private var currentNonce: String?
    
    func generateNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return nonce
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // MARK: - Event Operations
    
    func createEvent(_ event: Event) async throws -> String {
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        var eventData: [String: Any] = [
            "name": event.name,
            "localId": event.id.uuidString,  // Store the local UUID for consistency
            "createdBy": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "lastModified": FieldValue.serverTimestamp(),
            "collaborators": [userId: true]
        ]

        // Include inviteCode if present (for sharing persistence)
        if let inviteCode = event.inviteCode {
            eventData["inviteCode"] = inviteCode
        }
        
        let docRef = try await db.collection("events").addDocument(data: eventData)
        
        // Save subcollections
        try await saveMembers(event.members, eventId: docRef.documentID)
        try await saveExpenses(event.expenses, eventId: docRef.documentID)
        try await saveDonations(event.donations, eventId: docRef.documentID)
        
        return docRef.documentID
    }
    
    func updateEvent(_ event: Event, eventId: String) async throws {
        guard user?.uid != nil else {
            throw FirebaseError.notAuthenticated
        }
        
        let eventRef = db.collection("events").document(eventId)

        var updateData: [String: Any] = [
            "name": event.name,
            "lastModified": FieldValue.serverTimestamp()
        ]

        // Persist inviteCode if present (critical for sharing persistence)
        if let inviteCode = event.inviteCode {
            updateData["inviteCode"] = inviteCode
        }

        try await eventRef.updateData(updateData)
        
        // Update subcollections
        try await saveMembers(event.members, eventId: eventId)
        try await saveExpenses(event.expenses, eventId: eventId)
        try await saveDonations(event.donations, eventId: eventId)
    }
    
    func deleteEvent(eventId: String) async throws {
        let eventRef = db.collection("events").document(eventId)
        
        // Delete subcollections first
        try await deleteSubcollection(eventRef.collection("members"))
        try await deleteSubcollection(eventRef.collection("expenses"))
        try await deleteSubcollection(eventRef.collection("donations"))
        
        // Delete the event
        try await eventRef.delete()
    }
    
    private func deleteSubcollection(_ collection: CollectionReference) async throws {
        let snapshot = try await collection.getDocuments()
        for document in snapshot.documents {
            try await document.reference.delete()
        }
    }
    
    // MARK: - Subcollection Operations
    
    private func saveMembers(_ members: [Member], eventId: String) async throws {
        let batch = db.batch()
        let membersRef = db.collection("events").document(eventId).collection("members")
        
        // Fetch existing members to compare
        let snapshot = try await membersRef.getDocuments()
        let newIds = Set(members.map { $0.id.uuidString })
        
        // Delete members that no longer exist
        for doc in snapshot.documents {
            if !newIds.contains(doc.documentID) {
                batch.deleteDocument(doc.reference)
            }
        }
        
        // Add or update members
        for member in members {
            let docRef = membersRef.document(member.id.uuidString)
            batch.setData([
                "name": member.name,
                "type": member.type.rawValue
            ], forDocument: docRef, merge: true)
        }
        
        try await batch.commit()
    }
    
    private func saveExpenses(_ expenses: [Expense], eventId: String) async throws {
        let batch = db.batch()
        let expensesRef = db.collection("events").document(eventId).collection("expenses")
        
        // Fetch existing expenses to compare
        let snapshot = try await expensesRef.getDocuments()
        let newIds = Set(expenses.map { $0.id.uuidString })
        
        // Delete expenses that no longer exist
        for doc in snapshot.documents {
            if !newIds.contains(doc.documentID) {
                batch.deleteDocument(doc.reference)
            }
        }
        
        // Add or update expenses
        for expense in expenses {
            let docRef = expensesRef.document(expense.id.uuidString)
            let contributorsData = expense.contributors.map { contributor in
                [
                    "id": contributor.id.uuidString,
                    "name": contributor.name, 
                    "amount": NSDecimalNumber(decimal: contributor.amount)
                ]
            }
            
            batch.setData([
                "description": expense.description,
                "amount": NSDecimalNumber(decimal: expense.amount),
                "paidBy": expense.paidBy,
                "notes": expense.notes,
                "optOut": expense.optOut,
                "date": expense.date,
                "contributors": contributorsData
            ], forDocument: docRef, merge: true)
        }
        
        try await batch.commit()
    }
    
    private func saveDonations(_ donations: [Donation], eventId: String) async throws {
        let batch = db.batch()
        let donationsRef = db.collection("events").document(eventId).collection("donations")
        
        // Fetch existing donations to compare
        let snapshot = try await donationsRef.getDocuments()
        let newIds = Set(donations.map { $0.id.uuidString })
        
        // Delete donations that no longer exist
        for doc in snapshot.documents {
            if !newIds.contains(doc.documentID) {
                batch.deleteDocument(doc.reference)
            }
        }
        
        // Add or update donations
        for donation in donations {
            let docRef = donationsRef.document(donation.id.uuidString)
            batch.setData([
                "amount": NSDecimalNumber(decimal: donation.amount),
                "notes": donation.notes,
                "date": donation.date
            ], forDocument: docRef, merge: true)
        }
        
        try await batch.commit()
    }
    
    // MARK: - Fetching Events
    
    func fetchEvent(eventId: String) async throws -> Event? {
        guard user != nil else {
            throw FirebaseError.notAuthenticated
        }
        
        let document = try await db.collection("events").document(eventId).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        // Fetch subcollections
        let members = try await fetchMembers(eventId: eventId)
        let expenses = try await fetchExpenses(eventId: eventId)
        let donations = try await fetchDonations(eventId: eventId)
        
        let event = createEventFromFirebase(
            data: data,
            eventId: eventId,
            members: members,
            expenses: expenses,
            donations: donations
        )
        
        return event
    }
    
    func fetchEvents() async throws -> [Event] {
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let snapshot = try await db.collection("events")
            .whereFilter(Filter.orFilter([
                Filter.whereField("createdBy", isEqualTo: userId),
                Filter.whereField("collaborators.\(userId)", isEqualTo: true)
            ]))
            .getDocuments()
        
        var events: [Event] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let eventId = document.documentID
            
            // Fetch subcollections
            let members = try await fetchMembers(eventId: eventId)
            let expenses = try await fetchExpenses(eventId: eventId)
            let donations = try await fetchDonations(eventId: eventId)
            
            let event = createEventFromFirebase(
                data: data,
                eventId: eventId,
                members: members,
                expenses: expenses,
                donations: donations
            )
            
            events.append(event)
        }
        
        return events
    }
    
    private func fetchMembers(eventId: String) async throws -> [Member] {
        let snapshot = try await db.collection("events").document(eventId).collection("members").getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let name = data["name"] as? String,
                  let typeRaw = data["type"] as? String,
                  let type = MemberType(rawValue: typeRaw) else { return nil }
            
            return Member(id: UUID(uuidString: doc.documentID) ?? UUID(), name: name, type: type)
        }
    }
    
    private func fetchExpenses(eventId: String) async throws -> [Expense] {
        let snapshot = try await db.collection("events").document(eventId).collection("expenses").getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let description = data["description"] as? String,
                  let paidBy = data["paidBy"] as? String else { return nil }
            
            let amount: Decimal
            if let decimalNumber = data["amount"] as? NSDecimalNumber {
                amount = decimalNumber.decimalValue
            } else if let doubleValue = data["amount"] as? Double {
                amount = Decimal(doubleValue)
            } else {
                return nil
            }
            
            let contributorsData = data["contributors"] as? [[String: Any]] ?? []
            let contributors = contributorsData.compactMap { contributorData -> Contributor? in
                guard let name = contributorData["name"] as? String else { return nil }
                
                let amount: Decimal
                if let decimalNumber = contributorData["amount"] as? NSDecimalNumber {
                    amount = decimalNumber.decimalValue
                } else if let doubleValue = contributorData["amount"] as? Double {
                    amount = Decimal(doubleValue)
                } else {
                    return nil
                }
                
                // Parse contributor ID if it exists, otherwise generate a new one
                let contributorId: UUID
                if let idString = contributorData["id"] as? String,
                   let uuid = UUID(uuidString: idString) {
                    contributorId = uuid
                } else {
                    contributorId = UUID()
                }
                
                return Contributor(id: contributorId, name: name, amount: amount)
            }
            
            return Expense(
                id: UUID(uuidString: doc.documentID) ?? UUID(),
                description: description,
                amount: amount,
                paidBy: paidBy,
                notes: data["notes"] as? String ?? "",
                optOut: data["optOut"] as? Bool ?? false,
                contributors: contributors,
                date: (data["date"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }
    
    private func fetchDonations(eventId: String) async throws -> [Donation] {
        let snapshot = try await db.collection("events").document(eventId).collection("donations").getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            let amount: Decimal
            if let decimalNumber = data["amount"] as? NSDecimalNumber {
                amount = decimalNumber.decimalValue
            } else if let doubleValue = data["amount"] as? Double {
                amount = Decimal(doubleValue)
            } else {
                return nil
            }
            
            return Donation(
                id: UUID(uuidString: doc.documentID) ?? UUID(),
                amount: amount,
                notes: data["notes"] as? String ?? "",
                date: (data["date"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }
    
    // MARK: - Sharing
    
    func createInviteCode(for eventId: String) async throws -> String {
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }

        // Clean up old invite codes for this event to prevent accumulation
        let existingInvites = try await db.collection("invites")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()

        // Delete old invite codes for this event
        for document in existingInvites.documents {
            try await document.reference.delete()
        }

        // Generate a new 6-character invite code
        let code = generateInviteCode()

        // Save the mapping
        try await db.collection("invites").document(code).setData([
            "eventId": eventId,
            "createdBy": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": FieldValue.serverTimestamp() // Add expiration logic if needed
        ])

        return code
    }
    
    func joinEventWithCode(_ code: String) async throws -> String {
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        // Get the invite
        let inviteDoc = try await db.collection("invites").document(code).getDocument()
        
        guard let inviteData = inviteDoc.data(),
              let eventId = inviteData["eventId"] as? String else {
            throw FirebaseError.invalidInviteCode
        }
        
        // First, try to get the event to see if we already have access
        let eventRef = db.collection("events").document(eventId)
        let eventDoc = try? await eventRef.getDocument()
        
        // Check if we're already a collaborator
        if let data = eventDoc?.data(),
           let collaborators = data["collaborators"] as? [String: Bool],
           collaborators[userId] == true {
            // Already a collaborator, just return the event ID
            return eventId
        }
        
        // Try to add user as collaborator
        // Note: This will fail if the user doesn't have write permission
        // The proper solution is to use a Cloud Function that has admin privileges
        do {
            try await eventRef.updateData([
                "collaborators.\(userId)": true
            ])
        } catch {
            // For now, we'll need to handle this differently
            // The event creator needs to manually add collaborators, or we need Cloud Functions
            throw FirebaseError.permissionDenied
        }
        
        return eventId
    }
    
    private func generateInviteCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map{ _ in letters.randomElement()! })
    }
    
    // MARK: - Helper Functions
    
    private func createEventFromFirebase(data: [String: Any], 
                                         eventId: String, 
                                         members: [Member], 
                                         expenses: [Expense], 
                                         donations: [Donation]) -> Event {
        // Parse timestamps first
        let createdAt: Date
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            createdAt = createdAtTimestamp.dateValue()
        } else {
            createdAt = Date()
        }
        
        // Create event with proper timestamps
        var event = Event(
            name: data["name"] as? String ?? "",
            members: members,
            expenses: expenses,
            donations: donations,
            createdAt: createdAt
        )
        
        // CRITICAL: Set the Firebase ID so we can match events properly
        event.firebaseId = eventId
        
        // If there's a stored UUID in Firebase, use it to maintain consistency
        if let storedId = data["localId"] as? String,
           let uuid = UUID(uuidString: storedId) {
            event.id = uuid
        }
        
        // Parse lastModified timestamp
        if let lastModifiedTimestamp = data["lastModified"] as? Timestamp {
            event.lastModified = lastModifiedTimestamp.dateValue()
        }
        
        // Parse other Firebase fields
        event.createdBy = data["createdBy"] as? String
        event.inviteCode = data["inviteCode"] as? String
        if let collaborators = data["collaborators"] as? [String: Bool] {
            event.collaborators = collaborators
        }
        
        return event
    }
    
    // MARK: - Real-time Listeners
    
    func listenToEvent(eventId: String, completion: @escaping (Event?) -> Void) -> ListenerRegistration {
        let listener = db.collection("events").document(eventId).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self,
                  let data = snapshot?.data(),
                  error == nil else {
                completion(nil)
                return
            }

            Task { [weak self] in
                guard let self = self else { return }
                do {
                    // Fetch all subcollections in parallel for better performance
                    async let membersTask = self.fetchMembers(eventId: eventId)
                    async let expensesTask = self.fetchExpenses(eventId: eventId)
                    async let donationsTask = self.fetchDonations(eventId: eventId)

                    let (members, expenses, donations) = try await (
                        membersTask,
                        expensesTask,
                        donationsTask
                    )

                    let event = self.createEventFromFirebase(
                        data: data,
                        eventId: eventId,
                        members: members,
                        expenses: expenses,
                        donations: donations
                    )

                    await MainActor.run {
                        completion(event)
                    }
                } catch {
                    completion(nil)
                }
            }
        }
        
        eventListeners.append(listener)
        return listener
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case missingNonce
    case missingToken
    case invalidToken
    case notAnonymous
    
    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid authentication credential"
        case .missingNonce:
            return "Missing authentication nonce"
        case .missingToken:
            return "Missing authentication token"
        case .invalidToken:
            return "Invalid authentication token"
        case .notAnonymous:
            return "Current user is not anonymous"
        }
    }
}

enum FirebaseError: LocalizedError {
    case notAuthenticated
    case invalidInviteCode
    case inviteCodeExpired
    case inviteCodeAlreadyUsed
    case inviteCodeGenerationFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidInviteCode:
            return "Invalid invite code"
        case .inviteCodeExpired:
            return "This invite code has expired"
        case .inviteCodeAlreadyUsed:
            return "This invite code has already been used"
        case .inviteCodeGenerationFailed:
            return "Failed to generate invite code, please try again"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        }
    }
}
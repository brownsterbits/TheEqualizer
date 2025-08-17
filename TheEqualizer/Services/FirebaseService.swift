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
            self?.user = user
            self?.isAuthenticated = user != nil
        }
    }
    
    func signInAnonymously() async throws {
        do {
            let result = try await Auth.auth().signInAnonymously()
            user = result.user
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
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
            user = result.user
            isAuthenticated = true
            
            // Update user profile in Firestore
            try await updateUserProfile(email: appleIDCredential.email)
        } catch {
            authError = error.localizedDescription
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
            user = result.user
            
            // Update user profile in Firestore
            try await updateUserProfile(email: appleIDCredential.email)
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }
    
    private func updateUserProfile(email: String?) async throws {
        guard let userId = user?.uid else { return }
        
        let userRef = db.collection("users").document(userId)
        try await userRef.setData([
            "email": email ?? "",
            "isPro": true, // Set based on subscription status
            "createdAt": FieldValue.serverTimestamp(),
            "lastLogin": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        user = nil
        isAuthenticated = false
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
        
        let eventData: [String: Any] = [
            "name": event.name,
            "localId": event.id.uuidString,  // Store the local UUID for consistency
            "createdBy": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "lastModified": FieldValue.serverTimestamp(),
            "collaborators": [userId: true]
        ]
        
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
        
        try await eventRef.updateData([
            "name": event.name,
            "lastModified": FieldValue.serverTimestamp()
        ])
        
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
        
        // Delete existing members
        let snapshot = try await membersRef.getDocuments()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Add new members
        for member in members {
            let docRef = membersRef.document(member.id.uuidString)
            batch.setData([
                "name": member.name,
                "type": member.type.rawValue
            ], forDocument: docRef)
        }
        
        try await batch.commit()
    }
    
    private func saveExpenses(_ expenses: [Expense], eventId: String) async throws {
        let batch = db.batch()
        let expensesRef = db.collection("events").document(eventId).collection("expenses")
        
        // Delete existing expenses
        let snapshot = try await expensesRef.getDocuments()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Add new expenses
        for expense in expenses {
            let docRef = expensesRef.document(expense.id.uuidString)
            let contributorsData = expense.contributors.map { contributor in
                ["name": contributor.name, "amount": contributor.amount]
            }
            
            batch.setData([
                "description": expense.description,
                "amount": expense.amount,
                "paidBy": expense.paidBy,
                "notes": expense.notes,
                "optOut": expense.optOut,
                "date": expense.date,
                "contributors": contributorsData
            ], forDocument: docRef)
        }
        
        try await batch.commit()
    }
    
    private func saveDonations(_ donations: [Donation], eventId: String) async throws {
        let batch = db.batch()
        let donationsRef = db.collection("events").document(eventId).collection("donations")
        
        // Delete existing donations
        let snapshot = try await donationsRef.getDocuments()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Add new donations
        for donation in donations {
            let docRef = donationsRef.document(donation.id.uuidString)
            batch.setData([
                "amount": donation.amount,
                "notes": donation.notes,
                "date": donation.date
            ], forDocument: docRef)
        }
        
        try await batch.commit()
    }
    
    // MARK: - Fetching Events
    
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
                  let amount = data["amount"] as? Double,
                  let paidBy = data["paidBy"] as? String else { return nil }
            
            let contributorsData = data["contributors"] as? [[String: Any]] ?? []
            let contributors = contributorsData.compactMap { contributorData -> Contributor? in
                guard let name = contributorData["name"] as? String,
                      let amount = contributorData["amount"] as? Double else { return nil }
                return Contributor(name: name, amount: amount)
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
            guard let amount = data["amount"] as? Double else { return nil }
            
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
        
        // Generate a 6-character invite code
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
        
        // Add user as collaborator
        let eventRef = db.collection("events").document(eventId)
        try await eventRef.updateData([
            "collaborators.\(userId)": true
        ])
        
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
        var event = Event(
            name: data["name"] as? String ?? "",
            members: members,
            expenses: expenses,
            donations: donations
        )
        
        // CRITICAL: Set the Firebase ID so we can match events properly
        event.firebaseId = eventId
        
        // If there's a stored UUID in Firebase, use it to maintain consistency
        if let storedId = data["localId"] as? String,
           let uuid = UUID(uuidString: storedId) {
            event.id = uuid
        }
        
        return event
    }
    
    // MARK: - Real-time Listeners
    
    func listenToEvent(eventId: String, completion: @escaping (Event?) -> Void) -> ListenerRegistration {
        let listener = db.collection("events").document(eventId).addSnapshotListener { [weak self] snapshot, error in
            guard let data = snapshot?.data(),
                  error == nil else {
                completion(nil)
                return
            }
            
            Task {
                do {
                    let members = try await self?.fetchMembers(eventId: eventId) ?? []
                    let expenses = try await self?.fetchExpenses(eventId: eventId) ?? []
                    let donations = try await self?.fetchDonations(eventId: eventId) ?? []
                    
                    let event = self?.createEventFromFirebase(
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
                    print("Error fetching event details: \(error)")
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
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidInviteCode:
            return "Invalid or expired invite code"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        }
    }
}
import SwiftUI

struct MembersView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingAddMember = false
    @State private var newMemberName = ""
    @State private var selectedMemberType: MemberType = .contributing
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        List {
            Section(header: Text("Contributing Members")) {
                if dataStore.contributingMembers.isEmpty {
                    Text("No contributing members added yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(dataStore.contributingMembers) { member in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.purple)
                            Text(member.name)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        deleteMember(at: indexSet, from: dataStore.contributingMembers)
                    }
                }
            }
            
            Section(header: Text("Reimbursement-Only Members")) {
                if dataStore.reimbursementMembers.isEmpty {
                    Text("No reimbursement-only members added yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(dataStore.reimbursementMembers) { member in
                        HStack {
                            Image(systemName: "person.badge.minus")
                                .foregroundColor(.orange)
                            Text(member.name)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        deleteMember(at: indexSet, from: dataStore.reimbursementMembers)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Members")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddMember = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberView(
                memberName: $newMemberName,
                memberType: $selectedMemberType,
                isPresented: $showingAddMember,
                onSave: addMember
            )
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func addMember() {
        let trimmedName = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            alertMessage = "Please enter a member name"
            showingAlert = true
            return
        }
        
        guard !dataStore.memberExists(name: trimmedName) else {
            alertMessage = "Member already exists"
            showingAlert = true
            return
        }
        
        dataStore.addMember(name: trimmedName, type: selectedMemberType)
        newMemberName = ""
        showingAddMember = false
    }
    
    private func deleteMember(at offsets: IndexSet, from members: [Member]) {
        for index in offsets {
            dataStore.removeMember(members[index])
        }
    }
}

struct AddMemberView: View {
    @Binding var memberName: String
    @Binding var memberType: MemberType
    @Binding var isPresented: Bool
    let onSave: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Member Information")) {
                    TextField("Member Name", text: $memberName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Member Type", selection: $memberType) {
                        ForEach(MemberType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section {
                    Text(memberType == .contributing ? 
                         "Contributing members share expenses equally" : 
                         "Reimbursement-only members can be reimbursed but don't share in expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Member")
            .navigationBarItems(
                leading: Button("Cancel") {
                    memberName = ""
                    isPresented = false
                },
                trailing: Button("Save") {
                    onSave()
                }
                .fontWeight(.bold)
            )
        }
    }
}
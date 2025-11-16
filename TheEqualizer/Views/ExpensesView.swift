import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingAddExpense = false
    @State private var isRefreshing = false
    
    var body: some View {
        List {
            if dataStore.expenses.isEmpty {
                Text("No expenses added yet")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                ForEach(dataStore.expenses) { expense in
                    ExpenseRowView(expense: expense)
                }
                .onDelete(perform: deleteExpense)
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshData()
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddExpense = true }) {
                    Image(systemName: "plus")
                        .font(.body)
                }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView()
        }
    }
    
    private func deleteExpense(at offsets: IndexSet) {
        for index in offsets {
            dataStore.removeExpense(dataStore.expenses[index])
        }
    }
    
    private func refreshData() async {
        await dataStore.refreshCurrentEvent()
    }
}

struct ExpenseRowView: View {
    @EnvironmentObject var dataStore: DataStore
    let expense: Expense
    @State private var isExpanded = false
    @State private var showingAddContributor = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main expense info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(expense.description)
                            .font(.headline)
                        if expense.optOut {
                            Text("Non-reimbursable")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Paid by \(expense.paidBy)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !expense.notes.isEmpty {
                        Text(expense.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(expense.amount.asCurrency())")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)

                    if expense.totalContributions > 0 {
                        Text("Net: $\(expense.remainingAmount.asCurrency())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Contributors
            if !expense.contributors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Direct Donations:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(expense.contributors) { contributor in
                        HStack {
                            Text("\(contributor.name): $\(contributor.amount.asCurrency())")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            Button(action: {
                                dataStore.removeContributor(from: expense, contributor: contributor)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .imageScale(.small)
                            }
                        }
                    }
                }
            }
            
            // Add contributor button
            if !expense.optOut && expense.remainingAmount > 0 {
                Button(action: { showingAddContributor = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Direct Donation")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .sheet(isPresented: $showingAddContributor) {
                    AddContributorView(expense: expense)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct AddExpenseView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.presentationMode) var presentationMode
    
    @State private var description = ""
    @State private var amount = ""
    @State private var selectedMember = ""
    @State private var notes = ""
    @State private var optOut = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var allMembers: [String] {
        dataStore.members.map { $0.name }.sorted()
    }
    
    var body: some View {
        NavigationView {
            Form {
                if allMembers.isEmpty {
                    Section {
                        Text("Please add members before adding expenses")
                            .foregroundColor(.orange)
                            .font(.callout)
                    }
                } else {
                    Section(header: Text("Expense Details")) {
                        TextField("Description", text: $description)
                        
                        HStack {
                            Text("$")
                            TextField("Amount", text: $amount)
                                .keyboardType(.decimalPad)
                        }
                        
                        Picker("Paid By", selection: $selectedMember) {
                            Text("Select Member").tag("")
                            ForEach(allMembers, id: \.self) { member in
                                Text(member).tag(member)
                            }
                        }
                        
                        TextField("Notes (optional)", text: $notes)
                    }
                    
                    Section {
                        Toggle("Non-reimbursable expense", isOn: $optOut)
                        
                        if optOut {
                            Text("This expense won't be included in reimbursements")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveExpense()
                }
                .fontWeight(.bold)
            )
            .alert("Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func saveExpense() {
        // Check if there are members first
        guard !allMembers.isEmpty else {
            alertMessage = "Please add members before adding expenses"
            showingAlert = true
            return
        }
        
        guard !description.isEmpty else {
            alertMessage = "Please enter a description"
            showingAlert = true
            return
        }
        
        guard let amountValue = Decimal(string: amount), amountValue > 0 else {
            alertMessage = "Please enter a valid amount"
            showingAlert = true
            return
        }
        
        guard !selectedMember.isEmpty else {
            alertMessage = "Please select who paid"
            showingAlert = true
            return
        }
        
        // Add the expense
        dataStore.addExpense(
            description: description,
            amount: amountValue,
            paidBy: selectedMember,
            notes: notes,
            optOut: optOut
        )
        
        // Dismiss after a small delay to prevent UI hang
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct AddContributorView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.presentationMode) var presentationMode
    
    let expense: Expense
    @State private var selectedMember = ""
    @State private var amount = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var availableMembers: [String] {
        dataStore.contributingMembers
            .map { $0.name }
            .filter { name in
                name != expense.paidBy &&
                !expense.contributors.contains { $0.name == name }
            }
            .sorted()
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Direct Donation Details")) {
                    Picker("Contributing Member", selection: $selectedMember) {
                        Text("Select Member").tag("")
                        ForEach(availableMembers, id: \.self) { member in
                            Text(member).tag(member)
                        }
                    }
                    
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    Text("Maximum: $\(expense.remainingAmount.asCurrency())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Text("Money given directly by one member to another to help split expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Direct Donation")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Add") {
                    addContributor()
                }
                .fontWeight(.bold)
            )
            .alert("Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            // Validate selection when view appears - reset if not in available members
            // This prevents Picker errors when @State persists invalid selections
            if !selectedMember.isEmpty && !availableMembers.contains(selectedMember) {
                selectedMember = ""
            }
        }
    }
    
    private func addContributor() {
        guard !selectedMember.isEmpty else {
            alertMessage = "Please select a contributor"
            showingAlert = true
            return
        }
        
        guard let amountValue = Decimal(string: amount), amountValue > 0 else {
            alertMessage = "Please enter a valid amount"
            showingAlert = true
            return
        }
        
        guard amountValue <= expense.remainingAmount else {
            alertMessage = "Amount exceeds remaining expense amount"
            showingAlert = true
            return
        }
        
        // Add the contributor
        dataStore.addContributor(to: expense, name: selectedMember, amount: amountValue)
        
        // Dismiss after a small delay to prevent UI hang
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            presentationMode.wrappedValue.dismiss()
        }
    }
}
import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingAddExpense = false
    
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
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddExpense = true }) {
                    Image(systemName: "plus")
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
                    Text("$\(expense.amount, specifier: "%.2f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                    
                    if expense.totalContributions > 0 {
                        Text("Net: $\(expense.remainingAmount, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Contributors
            if !expense.contributors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contributors:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(expense.contributors) { contributor in
                        HStack {
                            Text("\(contributor.name): $\(contributor.amount, specifier: "%.2f")")
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
                        Text("Add Contributor")
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
        guard !description.isEmpty else {
            alertMessage = "Please enter a description"
            showingAlert = true
            return
        }
        
        guard let amountValue = Double(amount), amountValue > 0 else {
            alertMessage = "Please enter a valid amount"
            showingAlert = true
            return
        }
        
        guard !selectedMember.isEmpty else {
            alertMessage = "Please select who paid"
            showingAlert = true
            return
        }
        
        dataStore.addExpense(
            description: description,
            amount: amountValue,
            paidBy: selectedMember,
            notes: notes,
            optOut: optOut
        )
        
        presentationMode.wrappedValue.dismiss()
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
                Section(header: Text("Add Contributor")) {
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
                    
                    Text("Maximum: $\(expense.remainingAmount, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Contributor")
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
    }
    
    private func addContributor() {
        guard !selectedMember.isEmpty else {
            alertMessage = "Please select a contributor"
            showingAlert = true
            return
        }
        
        guard let amountValue = Double(amount), amountValue > 0 else {
            alertMessage = "Please enter a valid amount"
            showingAlert = true
            return
        }
        
        guard amountValue <= expense.remainingAmount else {
            alertMessage = "Amount exceeds remaining expense amount"
            showingAlert = true
            return
        }
        
        dataStore.addContributor(to: expense, name: selectedMember, amount: amountValue)
        presentationMode.wrappedValue.dismiss()
    }
}
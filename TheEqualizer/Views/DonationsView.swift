import SwiftUI

struct DonationsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingAddDonation = false
    
    var body: some View {
        List {
            if dataStore.donations.isEmpty {
                Text("No donations added yet")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                ForEach(dataStore.donations) { donation in
                    DonationRowView(donation: donation)
                }
                .onDelete(perform: deleteDonation)
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Anonymous Donations")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddDonation = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddDonation) {
            AddDonationView()
        }
    }
    
    private func deleteDonation(at offsets: IndexSet) {
        for index in offsets {
            dataStore.removeDonation(dataStore.donations[index])
        }
    }
}

struct DonationRowView: View {
    let donation: Donation
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anonymous Donation")
                    .font(.headline)
                
                if !donation.notes.isEmpty {
                    Text(donation.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                Text(donation.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("$\(donation.amount, specifier: "%.2f")")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
    }
}

struct AddDonationView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.presentationMode) var presentationMode
    
    @State private var amount = ""
    @State private var notes = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Donation Details")) {
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    TextField("Notes (optional)", text: $notes)
                }
                
                Section {
                    Text("Anonymous donations help reduce the amount each contributing member needs to pay")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Donation")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveDonation()
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
    
    private func saveDonation() {
        guard let amountValue = Double(amount), amountValue > 0 else {
            alertMessage = "Please enter a valid amount"
            showingAlert = true
            return
        }
        
        dataStore.addDonation(amount: amountValue, notes: notes)
        presentationMode.wrappedValue.dismiss()
    }
}
import SwiftUI

struct SettlementView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingExportOptions = false
    @State private var showingShareSheet = false
    @State private var exportedText = ""
    
    var settlements: (toContribute: [(member: String, amount: Double)], toReimburse: [(member: String, amount: Double)]) {
        let balances = dataStore.members.map { member in
            (member: member.name, balance: dataStore.balance(for: member.name))
        }
        
        let toContribute = balances.filter { $0.balance < 0 }.map { ($0.member, abs($0.balance.doubleValue)) }
        let toReimburse = balances.filter { $0.balance > 0 }.map { ($0.member, $0.balance.doubleValue) }
        
        return (toContribute, toReimburse)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if settlements.toContribute.isEmpty && settlements.toReimburse.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Everyone is settled up!")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("No payments needed")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    // Treasury contributions
                    if !settlements.toContribute.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                
                                Text("Contribute to Treasury")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(spacing: 10) {
                                ForEach(settlements.toContribute, id: \.member) { item in
                                    SettlementRow(
                                        person: item.member,
                                        amount: item.amount,
                                        type: .owes
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Treasury reimbursements
                    if !settlements.toReimburse.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                
                                Text("Reimburse from Treasury")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(spacing: 10) {
                                ForEach(settlements.toReimburse, id: \.member) { item in
                                    SettlementRow(
                                        person: item.member,
                                        amount: item.amount,
                                        type: .owed
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Export button
                    Button(action: { showingExportOptions = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Settlement")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                
                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle("Settlement")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(UIColor.systemGroupedBackground))
        .actionSheet(isPresented: $showingExportOptions) {
            ActionSheet(
                title: Text("Export Settlement"),
                buttons: [
                    .default(Text("Copy to Clipboard")) {
                        copyToClipboard()
                    },
                    .default(Text("Share")) {
                        shareSettlement()
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(text: exportedText)
        }
    }
    
    private func copyToClipboard() {
        exportedText = generateExportText()
        UIPasteboard.general.string = exportedText
    }
    
    private func shareSettlement() {
        exportedText = generateExportText()
        showingShareSheet = true
    }
    
    private func generateExportText() -> String {
        var text = "THE EQUALIZER - SETTLEMENT REPORT\n"
        text += "Generated: \(Date().formatted(date: .complete, time: .shortened))\n\n"
        
        text += "SUMMARY\n"
        text += "Total Expenses: $\(dataStore.totalExpenses.formatted())\n"
        text += "Reimbursable Expenses: $\(dataStore.reimbursableExpenses.formatted())\n"
        text += "Treasury Donations: $\(dataStore.totalDonations.formatted())\n"
        text += "Direct Donations: $\(dataStore.directContributions.formatted())\n"
        text += "Share per Contributing Member: $\(dataStore.sharePerPerson.formatted())\n\n"
        
        if !settlements.toContribute.isEmpty {
            text += "CONTRIBUTE TO TREASURY:\n"
            for item in settlements.toContribute {
                text += "\(item.member): $\(String(format: "%.2f", item.amount))\n"
            }
            text += "\n"
        }
        
        if !settlements.toReimburse.isEmpty {
            text += "REIMBURSE FROM TREASURY:\n"
            for item in settlements.toReimburse {
                text += "\(item.member): $\(String(format: "%.2f", item.amount))\n"
            }
        }
        
        return text
    }
}

struct SettlementRow: View {
    let person: String
    let amount: Double
    let type: SettlementType
    
    enum SettlementType {
        case owes, owed
        
        var color: Color {
            switch self {
            case .owes: return .red
            case .owed: return .green
            }
        }
        
        var icon: String {
            switch self {
            case .owes: return "arrow.down.circle"
            case .owed: return "arrow.up.circle"
            }
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
            
            Text(person)
                .font(.body)
            
            Spacer()
            
            Text("$\(String(format: "%.2f", amount))")
                .font(.headline)
                .foregroundColor(type.color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(type.color.opacity(0.1))
        .cornerRadius(8)
    }
}

// Share Sheet for iOS
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


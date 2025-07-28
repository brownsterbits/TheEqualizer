import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Financial Summary Cards
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        SummaryCard(
                            title: "Total Expenses",
                            amount: dataStore.totalExpenses,
                            color: .purple,
                            icon: "dollarsign.circle.fill"
                        )
                        
                        SummaryCard(
                            title: "Reimbursable",
                            amount: dataStore.reimbursableExpenses,
                            color: .blue,
                            icon: "arrow.left.arrow.right.circle.fill"
                        )
                    }
                    
                    HStack(spacing: 16) {
                        SummaryCard(
                            title: "Donations",
                            amount: dataStore.totalDonations,
                            color: .green,
                            icon: "gift.fill"
                        )
                        
                        SummaryCard(
                            title: "Direct Contributions",
                            amount: dataStore.directContributions,
                            color: .orange,
                            icon: "person.2.fill"
                        )
                    }
                }
                .padding(.horizontal)
                
                // Member Balances
                if !dataStore.members.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Member Balances")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            ForEach(dataStore.members) { member in
                                MemberBalanceRow(member: member)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Share Information
                if !dataStore.contributingMembers.isEmpty {
                    VStack(spacing: 8) {
                        Text("Share per Contributing Member")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("$\(dataStore.sharePerPerson, specifier: "%.2f")")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                        
                        Text("\(dataStore.contributingMembers.count) contributing members")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle("Summary")
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Double
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .imageScale(.large)
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("$\(amount, specifier: "%.2f")")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MemberBalanceRow: View {
    @EnvironmentObject var dataStore: DataStore
    let member: Member
    
    var balance: Double {
        dataStore.balance(for: member.name)
    }
    
    var balanceColor: Color {
        balance >= 0 ? .green : .red
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.headline)
                    
                    if member.type == .reimbursementOnly {
                        Text("Reimbursement Only")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(getPaidAmount(), specifier: "%.2f")", systemImage: "creditcard")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if member.type == .contributing {
                        Label("\(dataStore.sharePerPerson, specifier: "%.2f")", systemImage: "equal.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(balance >= 0 ? "Owed" : "Owes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("$\(abs(balance), specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(balanceColor)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private func getPaidAmount() -> Double {
        dataStore.expenses
            .filter { $0.paidBy == member.name && !$0.optOut }
            .reduce(0) { $0 + $1.amount }
    }
}
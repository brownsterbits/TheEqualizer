//
//  TheEqualizerTests.swift
//  TheEqualizerTests
//
//  Created by Chad Brown on 7/24/25.
//

import XCTest
@testable import TheEqualizer

extension Event {
    func balance(for memberName: String) -> Decimal {
        let totalPaid = expenses
            .filter { $0.paidBy == memberName && !$0.optOut }
            .reduce(0) { $0 + $1.amount }
        
        let totalContributed = expenses.reduce(Decimal(0)) { sum, expense in
            let contribution = expense.contributors.first { $0.name == memberName }
            return sum + (contribution?.amount ?? 0)
        }
        
        let totalReceived = expenses
            .filter { $0.paidBy == memberName }
            .reduce(0) { sum, expense in
                sum + expense.contributors.reduce(0) { $0 + $1.amount }
            }
        
        let isContributor = contributingMembers.contains { $0.name == memberName }
        let share = isContributor ? sharePerPerson : 0
        
        return totalPaid - totalReceived + totalContributed - share
    }
}

final class TheEqualizerTests: XCTestCase {
    
    func testEventSharePerPerson() {
        // Test with no members
        var event = Event(name: "Test Event")
        XCTAssertEqual(event.sharePerPerson, 0)
        
        // Test with members but no expenses
        event.members = [
            Member(name: "Alice", type: .contributing),
            Member(name: "Bob", type: .contributing)
        ]
        XCTAssertEqual(event.sharePerPerson, 0)
        
        // Test with members and expenses
        event.expenses = [
            Expense(description: "Dinner", amount: 100, paidBy: "Alice")
        ]
        XCTAssertEqual(event.sharePerPerson, 50)
        
        // Test with reimbursement-only member
        event.members.append(Member(name: "Charlie", type: .reimbursementOnly))
        XCTAssertEqual(event.sharePerPerson, 50) // Still 50 as Charlie is reimbursement only
    }
    
    func testEventBalance() {
        var event = Event(name: "Test Event")
        event.members = [
            Member(name: "Alice", type: .contributing),
            Member(name: "Bob", type: .contributing)
        ]
        event.expenses = [
            Expense(description: "Dinner", amount: 100, paidBy: "Alice"),
            Expense(description: "Taxi", amount: 50, paidBy: "Bob")
        ]
        
        // Alice paid 100, owes 75 (half of 150), balance = +25
        XCTAssertEqual(event.balance(for: "Alice"), 25)
        
        // Bob paid 50, owes 75 (half of 150), balance = -25
        XCTAssertEqual(event.balance(for: "Bob"), -25)
        
        // Unknown member has 0 balance
        XCTAssertEqual(event.balance(for: "Charlie"), 0)
    }
    
    func testMemberTypeEncoding() {
        XCTAssertEqual(MemberType.contributing.rawValue, "contributing")
        XCTAssertEqual(MemberType.reimbursementOnly.rawValue, "reimbursementOnly")
    }
}
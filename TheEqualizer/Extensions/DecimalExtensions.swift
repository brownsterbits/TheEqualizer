import Foundation

extension Decimal {
    /// Formats the decimal as a currency string with exactly 2 decimal places
    /// Example: 10.5 -> "10.50", 10.123456 -> "10.12"
    func asCurrency() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: self as NSDecimalNumber) ?? "0.00"
    }
}

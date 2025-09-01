import Foundation

extension Decimal {
    var doubleValue: Double {
        let number = NSDecimalNumber(decimal: self)
        let value = number.doubleValue
        // Check for invalid values and return 0 instead of NaN/Infinity
        if value.isNaN || value.isInfinite {
            return 0
        }
        return value
    }
    
    func formatted(as format: String = "%.2f") -> String {
        let value = self.doubleValue
        // Ensure we don't format NaN or Infinity
        if value.isNaN || value.isInfinite {
            return "$0.00"
        }
        return String(format: format, value)
    }
    
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "$0.00"
    }
}

func abs(_ value: Decimal) -> Decimal {
    return value < 0 ? -value : value
}
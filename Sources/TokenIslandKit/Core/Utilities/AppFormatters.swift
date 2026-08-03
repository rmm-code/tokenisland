import Foundation

enum AppFormatters {
    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return tokenFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func currency(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    static func percent(_ value: Double) -> String {
        percentFormatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    static func compactDuration(milliseconds: Int?) -> String {
        guard let milliseconds else { return "n/a" }
        if milliseconds >= 1_000 {
            return String(format: "%.1fs", Double(milliseconds) / 1_000)
        }
        return "\(milliseconds)ms"
    }
}

import Foundation

/// Sizes the way Finder shows them: decimal units, a decimal point, a non-breaking space before the unit.
public enum ByteFormat {
    public struct Parts: Equatable, Sendable {
        public let value: String
        public let unit: String

        public var text: String { value + "\u{00A0}" + unit }
    }

    public static func string(_ bytes: Int64) -> String {
        parts(bytes).text
    }

    public static func parts(_ bytes: Int64) -> Parts {
        let units = [
            CoreStrings.bytes, CoreStrings.kilobytes, CoreStrings.megabytes, CoreStrings.gigabytes,
            CoreStrings.terabytes,
        ]
        var value = Double(max(bytes, 0))
        var index = 0
        // Gigabytes and terabytes keep one decimal, so they roll over at 999.95.
        while index < units.count - 1, rounded(value, decimals(for: index)) >= 1000 {
            value /= 1000
            index += 1
        }
        let digits = decimals(for: index)
        let text = String(format: "%.\(digits)f", rounded(value, digits))
        return Parts(value: text, unit: units[index])
    }

    /// A transfer rate, such as "2.4 MB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        let parts = parts(Int64(bytesPerSecond.rounded()))
        return parts.value + "\u{00A0}" + parts.unit + CoreStrings.perSecond
    }

    /// A whole number with commas between thousands, such as "48,213".
    public static func grouped(_ number: Int) -> String {
        var digits = Array(String(abs(number)))
        var index = digits.count - 3
        while index > 0 {
            digits.insert(",", at: index)
            index -= 3
        }
        return (number < 0 ? "-" : "") + String(digits)
    }

    private static func decimals(for unitIndex: Int) -> Int {
        unitIndex >= 3 ? 1 : 0
    }

    private static func rounded(_ value: Double, _ digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        return (value * scale).rounded() / scale
    }
}

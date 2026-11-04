import Foundation

public enum TextChunker {
    /// Splits on Character boundaries so each chunk has <= maxUTF16 code units (default 20).
    /// Never returns empty chunks. A single Character larger than the budget becomes its own chunk.
    public static func chunks(_ text: String, maxUTF16: Int = 20) -> [String] {
        var result: [String] = []
        var current = ""
        var currentUnits = 0
        for ch in text {
            let units = ch.utf16.count
            if currentUnits > 0 && currentUnits + units > maxUTF16 {
                result.append(current)
                current = ""
                currentUnits = 0
            }
            current.append(ch)
            currentUnits += units
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

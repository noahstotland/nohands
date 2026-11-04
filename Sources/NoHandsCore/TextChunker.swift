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

    /// Like `chunks`, but any chunk still over budget (a single oversize grapheme cluster) is
    /// split on Unicode scalar boundaries (never inside a surrogate pair). Delivered sequentially,
    /// the pieces still compose in the receiving app.
    public static func deliveryChunks(_ text: String, maxUTF16: Int = 20) -> [String] {
        let budget = max(2, maxUTF16)
        var result: [String] = []
        for chunk in chunks(text, maxUTF16: maxUTF16) {
            if chunk.utf16.count <= budget { result.append(chunk); continue }
            var current = String.UnicodeScalarView()
            var units = 0
            for scalar in chunk.unicodeScalars {
                let n = scalar.value > 0xFFFF ? 2 : 1
                if units > 0 && units + n > budget {
                    result.append(String(current))
                    current = String.UnicodeScalarView()
                    units = 0
                }
                current.append(scalar)
                units += n
            }
            if !current.isEmpty { result.append(String(current)) }
        }
        return result
    }
}

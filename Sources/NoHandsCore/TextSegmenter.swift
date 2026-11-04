import Foundation

public enum TextSegment: Equatable, Sendable {
    case text(String)
    case key(Key)
}

public enum TextSegmenter {
    /// Splits text so newlines ("\n", "\r", "\r\n") and tabs become real key presses.
    public static func segments(_ text: String) -> [TextSegment] {
        var result: [TextSegment] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(.text(current)); current = "" }
        }
        for ch in text {
            switch ch {
            case "\n", "\r", "\r\n":
                flush(); result.append(.key(.return))
            case "\t":
                flush(); result.append(.key(.tab))
            default:
                current.append(ch)
            }
        }
        flush()
        return result
    }
}

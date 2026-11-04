import Foundation

/// A JSON value whose object keys keep their declared order when serialized. JSON schemas are fed to
/// constrained decoders (Ollama / llama.cpp) that emit properties in schema order, so order is semantic:
/// it is how we make the model write its `intent` restatement BEFORE the `actions` it derives from it.
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case int(Int)
    case bool(Bool)

    public static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case (.object(let x), .object(let y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.array(let x), .array(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.int(let x), .int(let y)): return x == y
        case (.bool(let x), .bool(let y)): return x == y
        default: return false
        }
    }

    /// Serialized with keys in declaration order.
    public var serialized: String {
        switch self {
        case .object(let pairs):
            return "{" + pairs.map { Self.quote($0.0) + ":" + $0.1.serialized }.joined(separator: ",") + "}"
        case .array(let items):
            return "[" + items.map(\.serialized).joined(separator: ",") + "]"
        case .string(let s): return Self.quote(s)
        case .int(let i): return String(i)
        case .bool(let b): return b ? "true" : "false"
        }
    }

    public var data: Data { Data(serialized.utf8) }

    /// Equivalent Foundation object (order lost), for callers that use JSONSerialization.
    public var foundationObject: Any {
        switch self {
        case .object(let pairs):
            var d: [String: Any] = [:]
            for (k, v) in pairs { d[k] = v.foundationObject }
            return d
        case .array(let items): return items.map(\.foundationObject)
        case .string(let s): return s
        case .int(let i): return i
        case .bool(let b): return b
        }
    }

    private static func quote(_ s: String) -> String {
        // JSONSerialization handles escaping; wrap in an array because fragments are not allowed on all OS versions.
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }
}

import Foundation

/// `disposition` of an agent-desktop result: what was delivered and whether a repeat is safe.
public struct DesktopDisposition: Equatable, Sendable {
    public var delivery: String
    public var retry: String
    public init(delivery: String, retry: String) { self.delivery = delivery; self.retry = retry }
}

/// A window listed in an `AMBIGUOUS_TARGET` error's `details.candidates`.
public struct DesktopWindowCandidate: Equatable, Sendable {
    public var id: String
    public var title: String
    public var isFocused: Bool
    public var visible: Bool
    public init(id: String, title: String, isFocused: Bool, visible: Bool) {
        self.id = id; self.title = title; self.isFocused = isFocused; self.visible = visible
    }
}

public struct DesktopError: Equatable, Sendable {
    public var code: String
    public var message: String
    public var suggestion: String?
    public var disposition: DesktopDisposition?
    public var candidates: [DesktopWindowCandidate]
    public var detailsKind: String?

    public init(code: String, message: String, suggestion: String? = nil, disposition: DesktopDisposition? = nil,
                candidates: [DesktopWindowCandidate] = [], detailsKind: String? = nil) {
        self.code = code; self.message = message; self.suggestion = suggestion
        self.disposition = disposition; self.candidates = candidates; self.detailsKind = detailsKind
    }

    /// True when agent-desktop says nothing reached the app, so a fallback or retry cannot double an effect.
    public var notDelivered: Bool { disposition?.delivery == "not_delivered" }
}

/// One agent-desktop response: `{version, ok, command, data | error}`.
public struct DesktopEnvelope: Sendable {
    public var ok: Bool
    public var command: String
    /// The `data` object re-serialized as JSON (a dictionary of `Any` is not Sendable); nil on error.
    public var dataJSON: Data?
    public var error: DesktopError?

    /// `data` is the envelope's `data` value: an object, or an array for list commands.
    public init(ok: Bool, command: String, data: Any?, error: DesktopError?) {
        self.ok = ok; self.command = command; self.error = error
        self.dataJSON = data.flatMap { JSONSerialization.isValidJSONObject($0) ? try? JSONSerialization.data(withJSONObject: $0) : nil }
    }

    /// The `data` object (JSON-serialization types); nil on error or when `data` is an array.
    public var data: [String: Any]? {
        dataJSON.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    /// `data` when it is an array of objects (`list-windows`), else nil.
    public var dataArray: [[String: Any]]? {
        dataJSON.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] }
    }

    /// `data.disposition` on success.
    public var disposition: DesktopDisposition? {
        (data?["disposition"] as? [String: Any]).flatMap(Self.disposition(from:))
    }

    /// Overlays open once an action settled: `data.surfaces` as `[{type:}]` or `[String]`; [] when absent.
    public var surfaces: [String] {
        guard let raw = data?["surfaces"] as? [Any] else { return [] }
        return raw.compactMap { entry in
            if let s = entry as? String { return s }
            return (entry as? [String: Any])?["type"] as? String
        }
    }

    /// nil when `data` is not a JSON object with a boolean `ok`.
    public static func decode(_ data: Data) -> DesktopEnvelope? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ok = root["ok"] as? Bool else { return nil }
        let command = root["command"] as? String ?? ""
        if ok { return DesktopEnvelope(ok: true, command: command, data: root["data"], error: nil) }
        let e = root["error"] as? [String: Any] ?? [:]
        let details = e["details"] as? [String: Any]
        let candidates = (details?["candidates"] as? [[String: Any]] ?? []).compactMap { c -> DesktopWindowCandidate? in
            guard let id = c["id"] as? String else { return nil }
            return DesktopWindowCandidate(id: id, title: c["title"] as? String ?? "",
                                          isFocused: c["is_focused"] as? Bool ?? false, visible: c["visible"] as? Bool ?? true)
        }
        let error = DesktopError(code: e["code"] as? String ?? "UNKNOWN", message: e["message"] as? String ?? "",
                                 suggestion: e["suggestion"] as? String,
                                 disposition: (e["disposition"] as? [String: Any]).flatMap(disposition(from:)),
                                 candidates: candidates, detailsKind: details?["kind"] as? String)
        return DesktopEnvelope(ok: false, command: command, data: nil, error: error)
    }

    /// The child did not answer in time. An observation delivered nothing; an action may have landed.
    public static func timeout(command: String, observation: Bool) -> DesktopEnvelope {
        synthetic(code: "TIMEOUT", message: "agent-desktop timed out", command: command, observation: observation)
    }

    /// The child could not be run or produced no envelope.
    public static func processFailure(command: String, message: String, observation: Bool) -> DesktopEnvelope {
        synthetic(code: "PROCESS_FAILED", message: message, command: command, observation: observation)
    }

    /// The caller's task was cancelled while the child ran.
    public static func cancelled(command: String, observation: Bool) -> DesktopEnvelope {
        synthetic(code: "CANCELLED", message: "cancelled", command: command, observation: observation)
    }

    private static func synthetic(code: String, message: String, command: String, observation: Bool) -> DesktopEnvelope {
        let d = observation ? DesktopDisposition(delivery: "not_delivered", retry: "safe")
                            : DesktopDisposition(delivery: "unknown", retry: "unsafe")
        return DesktopEnvelope(ok: false, command: command, data: nil,
                               error: DesktopError(code: code, message: message, disposition: d))
    }

    private static func disposition(from o: [String: Any]) -> DesktopDisposition? {
        guard let delivery = o["delivery"] as? String else { return nil }
        return DesktopDisposition(delivery: delivery, retry: o["retry"] as? String ?? "unsafe")
    }
}

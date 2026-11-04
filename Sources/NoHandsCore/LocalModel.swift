import Foundation

public enum LocalModelStatus: Equatable, Sendable {
    case notRunning, modelMissing, downloading(Double?), downloadFailed, ready
}

public enum PullEvent: Equatable, Sendable {
    case progress(Double?), success, error(String)

    /// Parses one NDJSON line of Ollama's `/api/pull` stream; nil for blank or undecodable lines.
    public static func parse(line: String) -> PullEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let o = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else { return nil }
        if let e = o["error"] as? String { return .error(e) }
        if o["status"] as? String == "success" { return .success }
        if let total = (o["total"] as? NSNumber)?.doubleValue, total > 0,
           let done = (o["completed"] as? NSNumber)?.doubleValue {
            return .progress(min(max(done / total, 0), 1))
        }
        return .progress(nil)
    }
}

public enum LocalModelMenu {
    public static func text(_ s: LocalModelStatus, model: String, ollamaInstalled: Bool) -> String {
        switch s {
        case .notRunning: return ollamaInstalled ? "Start Ollama" : "Install Ollama…"
        case .modelMissing: return "Download local model (≈ \(approxDownloadGB(model: model)) GB)"
        case .downloading(let p):
            if let p { return "Downloading local model… \(Int((p * 100).rounded()))%" }
            return "Downloading local model…"
        case .downloadFailed: return "Download failed: retry"
        case .ready: return "Local model: ready (\(model))"
        }
    }

    public static func actionable(_ s: LocalModelStatus) -> Bool {
        switch s {
        case .notRunning, .modelMissing, .downloadFailed: return true
        case .downloading, .ready: return false
        }
    }

    public static func approxDownloadGB(model: String) -> String {
        switch model {
        case "qwen2.5:7b-instruct": return "4.7"
        case "qwen2.5:3b-instruct": return "1.9"
        default: return "?"
        }
    }
}

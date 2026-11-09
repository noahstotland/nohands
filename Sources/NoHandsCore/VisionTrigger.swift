import Foundation

/// When the task loop sends a picture of the focused window with the next step.
public enum VisionTrigger {
    /// True when the previous step failed on a named target that was missing or stale (`no element named …`,
    /// `element changed, …`), or the model asked with `look`. `no label N` is not a trigger: that is a misnumbered
    /// label, not an invisible element. (The model answering `stuck` is the third trigger; the runner owns it.)
    public static func wantsPicture(lastFailure: String?, lastActions: [Action]) -> Bool {
        if lastActions.contains(.look) { return true }
        guard let f = lastFailure else { return false }
        return f.hasPrefix("no element") || f.hasPrefix("element changed")
    }
}

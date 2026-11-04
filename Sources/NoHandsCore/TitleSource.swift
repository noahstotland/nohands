import Foundation
import CoreGraphics

public enum TitleSource {
    static let valueFallbackRoles: Set<String> = [
        "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXMenuItem", "AXTab",
    ]

    /// Whether AXValue may be used as a title fallback: only for control roles whose value is a short
    /// state/selection label. Editable text, cells, rows and other content hold user data (and titles are
    /// sent to an LLM), so they never fall back to the value.
    public static func allowsValueFallback(role: String, subrole: String?) -> Bool {
        if subrole == "AXSecureTextField" || role == "AXSecureTextField" { return false }
        return valueFallbackRoles.contains(role)
    }

    public static let secureFieldTitle = "password field"
}

public enum AppNameMatcher {
    /// Case-insensitive: exact, then prefix, then contains. Returns the first matching candidate's id.
    /// `allowContains: false` (installed apps that are not running) limits matching to exact, then prefix.
    public static func best<ID>(for query: String, in candidates: [(name: String, id: ID)], allowContains: Bool = true) -> ID? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        let c = candidates.map { ($0.id, $0.name.lowercased()) }
        return (c.first { $0.1 == q } ?? c.first { $0.1.hasPrefix(q) } ?? (allowContains ? c.first { $0.1.contains(q) } : nil))?.0
    }
}

extension UIElementInfo {
    /// Center of the frame clipped to the screen (CG coordinates) it overlaps most, so elements
    /// partly off-screen are clicked on their visible part. Falls back to the frame center.
    public func clickPoint(screens: [CGRect]) -> CGPoint {
        var best: CGRect?
        var bestArea: CGFloat = 0
        for s in screens {
            let i = frame.intersection(s)
            if !i.isNull, i.width * i.height > bestArea { best = i; bestArea = i.width * i.height }
        }
        let r = best ?? frame
        return CGPoint(x: r.midX, y: r.midY)
    }
}

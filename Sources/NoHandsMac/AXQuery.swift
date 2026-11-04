import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import NoHandsCore

/// Queries the frontmost app's accessibility tree.
/// Threading contract: all mutable state (`elements`) is guarded by `lock`; every method may be called
/// from any thread. Returned ids are only valid until the next `actionableElements()` call.
public final class AXQuery: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Int: AXUIElement] = [:]

    static let maxDepth = 12
    static let maxNodes = 2000
    static let budget: Duration = .milliseconds(150)
    static let actionableRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXMenuItem", "AXMenuBarItem", "AXTab", "AXSlider", "AXComboBox",
        "AXCell", "AXRow", "AXDisclosureTriangle", "AXIncrementor", "AXDecrementor",
    ]

    public init() {}

    public var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    public func element(for id: Int) -> AXUIElement? {
        lock.withLock { elements[id] }
    }

    public func actionableElements() -> [UIElementInfo] {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            lock.withLock { elements = [:] }
            return []
        }
        let screens = Self.screenRectsCG()
        var walker = Walker(screens: screens, deadline: ContinuousClock.now.advanced(by: Self.budget))
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.05)

        // Menu bar first (cheap, always present), then windows (sheets/popovers), then plain children.
        if let bar = Self.element(appEl, kAXMenuBarAttribute) {
            walker.visit(bar, depth: 1, descend: true, stopAtMenuBarItems: true)
        }
        for w in Self.elements(appEl, kAXWindowsAttribute) { walker.visit(w, depth: 1, descend: true) }
        for c in Self.elements(appEl, kAXChildrenAttribute) { walker.visit(c, depth: 1, descend: true) }

        var infos: [UIElementInfo] = []
        var map: [Int: AXUIElement] = [:]
        for (i, found) in walker.found.enumerated() {
            infos.append(UIElementInfo(id: i, frame: found.frame, title: found.title, role: found.role))
            map[i] = found.element
        }
        lock.withLock { elements = map }
        return infos
    }

    // MARK: activation

    public func activate(appNamed name: String) -> Bool {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }

        let running = NSWorkspace.shared.runningApplications.compactMap { app -> (NSRunningApplication, String)? in
            guard let n = app.localizedName else { return nil }
            return (app, n.lowercased())
        }
        if let app = Self.bestMatch(q, in: running)?.0 {
            return app.activate()
        }

        var installed: [(URL, [String])] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for dir in ["/Applications", "/System/Applications", "/Applications/Utilities", home + "/Applications"] {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" {
                var names = [url.deletingPathExtension().lastPathComponent]
                if let info = Bundle(url: url)?.infoDictionary {
                    for k in ["CFBundleDisplayName", "CFBundleName"] {
                        if let s = info[k] as? String { names.append(s) }
                    }
                }
                installed.append((url, names.map { $0.lowercased() }))
            }
        }
        // Same ordering (exact, prefix, contains) across all names of all apps.
        let flat = installed.flatMap { entry in entry.1.map { (entry.0, $0) } }
        guard let url = Self.bestMatch(q, in: flat)?.0 else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        return true
    }

    static func bestMatch<T>(_ q: String, in items: [(T, String)]) -> (T, String)? {
        items.first { $0.1 == q } ?? items.first { $0.1.hasPrefix(q) } ?? items.first { $0.1.contains(q) }
    }

    // MARK: screens

    /// Screen frames in CG (top-left origin) coordinates, flipped using the PRIMARY screen height.
    static func screenRectsCG() -> [CGRect] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let h = primary.frame.height
        // The flip is its own inverse; toAppKit(rect) performs it.
        return screens.map { CoordinateMapper.toAppKit($0.frame, primaryScreenHeight: h) }
    }

    // MARK: attribute helpers

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        (attr(el, name) as? [AXUIElement]) ?? []
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        guard let s = attr(el, name) as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(120))
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attr(el, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    struct Found { var element: AXUIElement; var frame: CGRect; var title: String; var role: String }

    struct Walker {
        let screens: [CGRect]
        let deadline: ContinuousClock.Instant
        var found: [Found] = []
        var visited = 0
        var seen: [CFHashCode: [AXUIElement]] = [:]

        init(screens: [CGRect], deadline: ContinuousClock.Instant) {
            self.screens = screens
            self.deadline = deadline
        }

        var exhausted: Bool { visited >= AXQuery.maxNodes || ContinuousClock.now >= deadline }

        mutating func firstVisit(_ el: AXUIElement) -> Bool {
            let h = CFHash(el)
            if seen[h]?.contains(where: { CFEqual($0, el) }) == true { return false }
            seen[h, default: []].append(el)
            return true
        }

        mutating func visit(_ el: AXUIElement, depth: Int, descend: Bool, stopAtMenuBarItems: Bool = false) {
            guard depth <= AXQuery.maxDepth, !exhausted, firstVisit(el) else { return }
            visited += 1
            AXUIElementSetMessagingTimeout(el, 0.05)
            let role = AXQuery.string(el, kAXRoleAttribute) ?? ""
            if AXQuery.actionableRoles.contains(role), let f = AXQuery.frame(el), isVisible(f) {
                let title = AXQuery.string(el, kAXTitleAttribute)
                    ?? AXQuery.string(el, kAXDescriptionAttribute)
                    ?? AXQuery.string(el, kAXValueAttribute) ?? ""
                found.append(Found(element: el, frame: f, title: title, role: role))
            }
            // Menu bar items open menus whose contents are not on screen; do not descend into them.
            if stopAtMenuBarItems && role == "AXMenuBarItem" { return }
            if role == "AXMenuItem" { return }
            for c in AXQuery.elements(el, kAXChildrenAttribute) {
                if exhausted { return }
                visit(c, depth: depth + 1, descend: true, stopAtMenuBarItems: stopAtMenuBarItems)
            }
        }

        func isVisible(_ f: CGRect) -> Bool {
            guard f.origin.x.isFinite, f.origin.y.isFinite, f.width.isFinite, f.height.isFinite,
                  f.width > 0, f.height > 0 else { return false }
            return screens.contains { $0.intersects(f) }
        }
    }
}

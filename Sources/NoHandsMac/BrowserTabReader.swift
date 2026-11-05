import Foundation
import AppKit
import ApplicationServices
import NoHandsCore

/// Reads and acts on the frontmost browser's windows and tabs through Accessibility (no AppleScript, so no
/// Automation prompt). Chrome, Safari and most browsers expose the tab strip as an `AXTabGroup` of tab buttons;
/// a browser that hides it (Firefox) shows its windows without tabs, and a window then stands for itself.
extension AXQuery {
    /// Each window gets its own walk budget so one slow window cannot leave the rest unread; `tabTotalBudget`
    /// bounds the whole read.
    static let tabBudget: Duration = .milliseconds(500)
    static let tabTotalBudget: Duration = .milliseconds(1500)
    static let tabMaxNodes = 600
    static let tabMaxDepth = 8
    static let tabRoles: Set<String> = ["AXRadioButton", "AXTab"]

    func frontmostBrowserPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              Self.chromiumBundleIDs.contains(id) || Self.otherBrowserBundleIDs.contains(id) else { return nil }
        return app.processIdentifier
    }

    public func browserWindows() -> (app: String, windows: [BrowserWindow])? {
        guard let app = NSWorkspace.shared.frontmostApplication, frontmostBrowserPID() != nil else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.1)
        exposeChromiumTree(app, appEl)
        let focused = Self.element(appEl, kAXFocusedWindowAttribute)
        let overall = ContinuousClock.now.advanced(by: Self.tabTotalBudget)
        var deadline = overall
        var visited = 0
        func tabGroup(in el: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth <= Self.tabMaxDepth, visited < Self.tabMaxNodes, ContinuousClock.now < deadline else { return nil }
            visited += 1
            AXUIElementSetMessagingTimeout(el, 0.05)
            let role = Self.string(el, kAXRoleAttribute)
            if role == "AXTabGroup" { return el }
            if role == "AXWebArea" { return nil }   // a page's own tab lists are not the browser's
            for c in Self.elements(el, kAXChildrenAttribute) {
                if let g = tabGroup(in: c, depth: depth + 1) { return g }
            }
            return nil
        }
        var windows: [BrowserWindow] = []
        for w in Self.elements(appEl, kAXWindowsAttribute) {
            visited = 0
            deadline = min(overall, ContinuousClock.now.advanced(by: Self.tabBudget))
            var tabs: [BrowserTab] = []
            if let group = tabGroup(in: w, depth: 1) {
                for t in Self.elements(group, kAXChildrenAttribute) where Self.tabRoles.contains(Self.string(t, kAXRoleAttribute) ?? "") {
                    let title = Self.string(t, kAXTitleAttribute) ?? Self.string(t, kAXDescriptionAttribute) ?? ""
                    tabs.append(BrowserTab(id: browserToken(for: t, prefix: "t"), title: title, active: Self.isSelected(t)))
                }
            }
            windows.append(BrowserWindow(id: browserToken(for: w, prefix: "w"), title: Self.string(w, kAXTitleAttribute) ?? "",
                                         front: focused.map { CFEqual($0, w) } ?? false, tabs: tabs))
        }
        return (app.localizedName ?? app.bundleIdentifier ?? "Browser", windows)
    }

    public func closeBrowserTab(id: String) -> BrowserActionResult {
        guard let tab = browserElement(forToken: id) else { return .gone }
        guard let close = Self.closeButton(in: tab) else { return Self.alive(tab) ? .noControl : .gone }
        return Self.press(close)
    }

    public func closeBrowserWindow(id: String) -> BrowserActionResult {
        guard let window = browserElement(forToken: id) else { return .gone }
        guard let close = Self.element(window, kAXCloseButtonAttribute) else { return Self.alive(window) ? .noControl : .gone }
        return Self.press(close)
    }

    public func selectBrowserTab(id: String) -> BrowserActionResult {
        guard let tab = browserElement(forToken: id) else { return .gone }
        return Self.press(tab)
    }

    public func browserTabIsSelected(id: String) -> Bool {
        browserElement(forToken: id).map(Self.isSelected) ?? false
    }

    public func browserTabIsInFrontWindow(id: String) -> Bool {
        guard let tab = browserElement(forToken: id), let front = NSWorkspace.shared.frontmostApplication else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(tab, &pid) == .success, pid == front.processIdentifier,
              let window = Self.element(tab, kAXWindowAttribute) else { return false }
        let focused = Self.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
        return focused.map { CFEqual($0, window) } ?? false
    }

    /// A tab button's value is 1 for the selected tab.
    static func isSelected(_ tab: AXUIElement) -> Bool {
        (attr(tab, kAXValueAttribute) as? NSNumber)?.intValue == 1
    }

    /// A close button inside a tab (Safari exposes one; Chrome does not): a button with the close subrole or named Close.
    static func closeButton(in tab: AXUIElement) -> AXUIElement? {
        func find(_ el: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth <= 3 else { return nil }
            for c in elements(el, kAXChildrenAttribute) {
                if string(c, kAXRoleAttribute) == "AXButton" {
                    let name = (string(c, kAXTitleAttribute) ?? string(c, kAXDescriptionAttribute) ?? "").lowercased()
                    if string(c, kAXSubroleAttribute) == "AXCloseButton" || name == "close" || name == "close tab" { return c }
                }
                if let hit = find(c, depth: depth + 1) { return hit }
            }
            return nil
        }
        return find(tab, depth: 1)
    }

    private static func alive(_ el: AXUIElement) -> Bool {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) != .invalidUIElement
    }

    private static func press(_ el: AXUIElement) -> BrowserActionResult {
        switch AXUIElementPerformAction(el, kAXPressAction as CFString) {
        case .success: .done
        case .invalidUIElement: .gone
        default: .failed("couldn't press it")
        }
    }
}

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import NoHandsCore

/// Queries the frontmost app's accessibility tree.
/// Closed menu items are intentionally not collected (menu bar items are): "click edit" then
/// "click copy" works once the menu is open.
/// Threading contract: all mutable state (`elements`) is guarded by `lock`; every method may be called
/// from any thread. Returned ids are only valid until the next `actionableElements()` call.
public final class AXQuery: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Int: AXUIElement] = [:]
    private var exposedPids: Set<pid_t> = []
    /// Set when a pid is first exposed; cleared by `didJustExpose()`.
    private var justExposed = false
    /// Browser windows and tabs handed to the task loop as opaque ids, matched by `CFEqual` so one element keeps one
    /// id for the whole task. Cleared by `resetBrowserTokens()`; guarded by `lock`.
    private var browserTokens: [(token: String, element: AXUIElement)] = []

    static let maxDepth = 30   // YouTube links sit ~23 levels below the window
    public static let defaultMaxNodes = 2000
    public static let defaultBudget: Duration = .milliseconds(150)
    private let maxNodes: Int
    private let budget: Duration
    static let actionableRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXMenuItem", "AXMenuBarItem", "AXTab", "AXSlider", "AXComboBox",
        "AXCell", "AXRow", "AXDisclosureTriangle", "AXIncrementor", "AXDecrementor",
    ]

    static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
    ]

    /// The defaults keep voice commands snappy; the task loop's observations can afford a larger walk
    /// (web pages hold ~1000 nodes behind a busy browser toolbar).
    public init(budget: Duration = AXQuery.defaultBudget, maxNodes: Int = AXQuery.defaultMaxNodes) {
        self.budget = budget
        self.maxNodes = maxNodes
    }

    /// Chromium builds the page's accessibility tree lazily; flag it once per pid.
    /// The page tree appears ~0.5 s AFTER exposure and this never waits, so the first walk of a freshly exposed
    /// browser is thin. Callers that need page content check `didJustExpose()` and re-observe (the task loop
    /// settles then); the voice path accepts a thin first walk.
    func exposeChromiumTree(_ app: NSRunningApplication, _ appEl: AXUIElement) {
        guard let id = app.bundleIdentifier, Self.chromiumBundleIDs.contains(id) else { return }
        let pid = app.processIdentifier
        let first = lock.withLock {
            let inserted = exposedPids.insert(pid).inserted
            if inserted { justExposed = true }
            return inserted
        }
        guard first else { return }
        // Chrome answers with an error code but does start building the tree.
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// True once after a walk first exposed a Chromium app (see `exposeChromiumTree`); reading clears it.
    public func didJustExpose() -> Bool {
        lock.withLock {
            defer { justExposed = false }
            return justExposed
        }
    }

    private func focusedWindow() -> (app: NSRunningApplication, appEl: AXUIElement, window: AXUIElement)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.05)
        guard let w = Self.element(appEl, kAXFocusedWindowAttribute) else { return nil }
        return (app, appEl, w)
    }

    public func focusedWindowTitle() -> String? {
        guard let f = focusedWindow() else { return nil }
        return Self.string(f.window, kAXTitleAttribute)
    }

    /// URL of the first web area in the focused window, else the window's AXDocument.
    public func webURL() -> String? {
        guard let f = focusedWindow() else { return nil }
        exposeChromiumTree(f.app, f.appEl)
        var visited = 0
        let deadline = ContinuousClock.now.advanced(by: budget)
        func find(_ el: AXUIElement, depth: Int) -> String? {
            guard depth <= Self.maxDepth, visited < maxNodes, ContinuousClock.now < deadline else { return nil }
            visited += 1
            AXUIElementSetMessagingTimeout(el, 0.05)
            if Self.string(el, kAXRoleAttribute) == "AXWebArea" {
                return Self.urlString(Self.attr(el, "AXURL"))
            }
            for c in Self.elements(el, kAXChildrenAttribute) {
                if let u = find(c, depth: depth + 1) { return u }
            }
            return nil
        }
        if let u = find(f.window, depth: 1) { return u }
        return Self.urlString(Self.attr(f.window, "AXDocument"))
    }

    static func urlString(_ v: CFTypeRef?) -> String? {
        guard let v else { return nil }
        if CFGetTypeID(v) == CFURLGetTypeID() { return (v as! URL).absoluteString }
        if let s = v as? String, !s.isEmpty { return s }
        return nil
    }

    public func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    static let otherBrowserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera", "org.chromium.Chromium", "com.google.Chrome.beta", "com.google.Chrome.dev",
        "com.kagi.kagimacOS", "app.zen-browser.zen",
    ]

    public func frontmostIsBrowser() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Self.chromiumBundleIDs.contains(id) || Self.otherBrowserBundleIDs.contains(id)
    }

    /// A search box gets its own, larger walk: a page's field sits deep in the tree, behind the browser's
    /// toolbar, and the command is worth most of a second.
    static let searchBudget: Duration = .milliseconds(800)
    static let searchMaxNodes = 4000

    /// The page's search box (inside the first web area) when there is one, else the window's (a native
    /// search field, or a text field named "search"). Menus and the address bar are never candidates.
    public func searchFieldFrame() -> CGRect? {
        guard let f = focusedWindow() else { return nil }
        exposeChromiumTree(f.app, f.appEl)
        let screens = Self.screenRectsCG()
        var visited = 0
        let deadline = ContinuousClock.now.advanced(by: Self.searchBudget)
        func names(_ el: AXUIElement) -> [String] {
            [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXIdentifierAttribute]
                .compactMap { Self.string(el, $0) }
        }
        func find(_ el: AXUIElement, depth: Int, skippingWebAreas: Bool) -> CGRect? {
            guard depth <= Self.maxDepth, visited < Self.searchMaxNodes, ContinuousClock.now < deadline else { return nil }
            visited += 1
            AXUIElementSetMessagingTimeout(el, 0.05)
            let role = Self.string(el, kAXRoleAttribute) ?? ""
            if role == "AXMenuBar" || role == "AXMenuItem" || role == "AXMenu" { return nil }
            if skippingWebAreas && role == "AXWebArea" { return nil }
            if SearchField.roles.contains(role) {
                let subrole = Self.string(el, kAXSubroleAttribute)
                if SearchField.matches(role: role, subrole: subrole, names: names(el)),
                   let frame = Self.frame(el), frame.width > 0, frame.height > 0, screens.contains(where: { $0.intersects(frame) }) {
                    return frame
                }
            }
            for c in Self.elements(el, kAXChildrenAttribute) {
                if let hit = find(c, depth: depth + 1, skippingWebAreas: skippingWebAreas) { return hit }
            }
            return nil
        }
        // The page first: a browser's own toolbar also has text fields ("Address and search bar").
        func firstWebArea(_ el: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth <= Self.maxDepth, visited < Self.searchMaxNodes, ContinuousClock.now < deadline else { return nil }
            visited += 1
            AXUIElementSetMessagingTimeout(el, 0.05)
            if Self.string(el, kAXRoleAttribute) == "AXWebArea" { return el }
            for c in Self.elements(el, kAXChildrenAttribute) {
                if let w = firstWebArea(c, depth: depth + 1) { return w }
            }
            return nil
        }
        if let web = firstWebArea(f.window, depth: 1) {
            if let hit = find(web, depth: 1, skippingWebAreas: false) { return hit }
            visited = 0
        }
        return find(f.window, depth: 1, skippingWebAreas: true)
    }

    /// The id for a browser window or tab element (`prefix` "w" or "t"): the same element always gets the same id.
    func browserToken(for el: AXUIElement, prefix: String) -> String {
        lock.withLock {
            if let known = browserTokens.first(where: { CFEqual($0.element, el) }) { return known.token }
            let token = "\(prefix)\(browserTokens.count + 1)"
            browserTokens.append((token, el))
            return token
        }
    }

    func browserElement(forToken token: String) -> AXUIElement? {
        lock.withLock { browserTokens.first { $0.token == token }?.element }
    }

    public func resetBrowserTokens() { lock.withLock { browserTokens = [] } }

    public func element(for id: Int) -> AXUIElement? {
        lock.withLock { elements[id] }
    }

    public func actionableElements() -> [UIElementInfo] { actionableElements(screens: Self.screenRectsCG()) }

    /// `screens` (CG rects, see `screenRectsCG()`) is read by the caller on the main actor, so this walk can run
    /// on any thread without touching NSScreen.
    public func actionableElements(screens: [CGRect]) -> [UIElementInfo] {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            lock.withLock { elements = [:] }
            return []
        }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.05)
        exposeChromiumTree(app, appEl)   // may block briefly; must precede the walk deadline
        var walker = Walker(screens: screens, maxNodes: maxNodes, deadline: ContinuousClock.now.advanced(by: budget))

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
        guard let match = lookupApp(named: name) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let app = match.running {
            if app.isHidden { app.unhide() }
            if let url = app.bundleURL {
                // openApplication works where a plain activate() can be refused (cooperative activation).
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
                return true
            }
            return app.activate()
        }
        guard let url = match.bundleURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        return true
    }

    /// Opens `url` in the named app (nil when no such app) or in the default handler. Returns the handler's name.
    public func open(url: URL, appNamed: String?) -> String? {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let appNamed {
            guard let match = lookupApp(named: appNamed), let bundle = match.running?.bundleURL ?? match.bundleURL else { return nil }
            if let app = match.running, app.isHidden { app.unhide() }
            NSWorkspace.shared.open([url], withApplicationAt: bundle, configuration: config) { _, _ in }
            return match.running?.localizedName ?? Self.displayName(of: bundle)
        }
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            NSWorkspace.shared.open(url)
            return ""
        }
        NSWorkspace.shared.open([url], withApplicationAt: handler, configuration: config) { _, _ in }
        return Self.displayName(of: handler)
    }

    public func frontmostHasWindow() -> Bool { focusedWindow() != nil }

    // MARK: window geometry

    /// AX reports window frames in CG (top-left origin) coordinates already.
    public func focusedWindowFrame() -> CGRect? {
        guard let f = focusedWindow() else { return nil }
        return Self.frame(f.window)
    }

    /// Position first (so a window that would overflow its current screen can still shrink), then size, then
    /// position again: apps clamp the size to their minimum and some only honour the origin once the size fits.
    public func setFocusedWindowFrame(_ frame: CGRect) -> Bool {
        guard let f = focusedWindow() else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(f.window, kAXPositionAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        var origin = frame.origin, size = frame.size
        guard let p = AXValueCreate(.cgPoint, &origin), let s = AXValueCreate(.cgSize, &size) else { return false }
        AXUIElementSetMessagingTimeout(f.window, 0.5)
        let moved = AXUIElementSetAttributeValue(f.window, kAXPositionAttribute as CFString, p)
        let sized = AXUIElementSetAttributeValue(f.window, kAXSizeAttribute as CFString, s)
        _ = AXUIElementSetAttributeValue(f.window, kAXPositionAttribute as CFString, p)
        return moved == .success || sized == .success
    }

    static func displayName(of bundle: URL) -> String {
        let info = Bundle(url: bundle)?.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
            ?? bundle.deletingPathExtension().lastPathComponent
    }

    private struct AppMatch { var running: NSRunningApplication?; var bundleURL: URL? }

    /// Running apps first (exact, prefix, contains on the localized name), then installed ones (exact, prefix).
    private func lookupApp(named name: String) -> AppMatch? {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningCands = running.enumerated().compactMap { (i, app) in app.localizedName.map { (name: $0, id: i) } }
        if let i = AppNameMatcher.best(for: q, in: runningCands) {
            return AppMatch(running: running[i], bundleURL: running[i].bundleURL)
        }

        var installed: [(url: URL, names: [String])] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for dir in ["/Applications", "/System/Applications", "/Applications/Utilities",
                    "/System/Applications/Utilities", home + "/Applications"] {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" {
                var names = [url.deletingPathExtension().lastPathComponent]
                if let info = Bundle(url: url)?.infoDictionary {
                    for k in ["CFBundleDisplayName", "CFBundleName"] {
                        if let s = info[k] as? String { names.append(s) }
                    }
                }
                installed.append((url, names))
            }
        }
        let flat = installed.flatMap { e in e.names.map { (name: $0, id: e.url) } }
        guard let url = AppNameMatcher.best(for: q, in: flat, allowContains: false) else { return nil }
        return AppMatch(running: nil, bundleURL: url)
    }

    // MARK: screens

    /// Screen frames in CG (top-left origin) coordinates, flipped using the PRIMARY screen height.
    public static func screenRectsCG() -> [CGRect] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let h = primary.frame.height
        // The flip is its own inverse; toAppKit(rect) performs it.
        return screens.map { CoordinateMapper.toAppKit($0.frame, primaryScreenHeight: h) }
    }

    /// Screen areas minus menu bar and Dock, CG coordinates, in `NSScreen.screens` order like `screenRectsCG()`.
    public static func visibleScreenRectsCG() -> [CGRect] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let h = primary.frame.height
        return screens.map { CoordinateMapper.toAppKit($0.visibleFrame, primaryScreenHeight: h) }
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
        let maxNodes: Int
        let deadline: ContinuousClock.Instant
        var found: [Found] = []
        var visited = 0
        var seen: [CFHashCode: [AXUIElement]] = [:]

        init(screens: [CGRect], maxNodes: Int, deadline: ContinuousClock.Instant) {
            self.screens = screens
            self.maxNodes = maxNodes
            self.deadline = deadline
        }

        var exhausted: Bool { visited >= maxNodes || ContinuousClock.now >= deadline }

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
                let subrole = AXQuery.string(el, kAXSubroleAttribute)
                let secure = subrole == "AXSecureTextField"
                var title = AXQuery.string(el, kAXTitleAttribute) ?? AXQuery.string(el, kAXDescriptionAttribute)
                if title == nil, !secure, !TitleSource.allowsValueFallback(role: role, subrole: subrole) {
                    title = AXQuery.string(el, "AXPlaceholderValue")
                }
                if title == nil, TitleSource.allowsValueFallback(role: role, subrole: subrole) {
                    title = AXQuery.string(el, kAXValueAttribute)
                }
                if title == nil, secure { title = TitleSource.secureFieldTitle }
                let finalTitle = title ?? ""
                found.append(Found(element: el, frame: f, title: finalTitle, role: role))
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

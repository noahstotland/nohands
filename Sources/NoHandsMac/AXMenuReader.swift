import Foundation
import AppKit
import ApplicationServices
import NoHandsCore

/// The frontmost app's menu items, for "menu <words>": read them, then press one by its index.
@MainActor public protocol MenuReading: AnyObject {
    /// The items in menu bar order, submenus included, the Apple menu left out. Their indexes stay valid for
    /// `press` until the next call.
    func entries() -> [MenuEntry]
    /// Presses the item at `index` of the last `entries()`. False when it is gone or the app refused.
    func press(_ index: Int) -> Bool
}

/// Reads and presses menu items through Accessibility. `AXPress` on an item in a closed menu runs it without
/// opening the menu on screen. The walk runs only when a menu action executes, within a time and item budget.
@MainActor public final class AXMenuReader: MenuReading {
    nonisolated static let budget: Duration = .milliseconds(200)
    nonisolated static let maxItems = 1500

    private var elements: [AXUIElement] = []

    public init() {}

    public func entries() -> [MenuEntry] {
        elements = []
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.1)
        guard let bar = AXQuery.element(appEl, kAXMenuBarAttribute) else { return [] }
        var walk = Walk(deadline: ContinuousClock.now.advanced(by: Self.budget))
        // The first menu bar item is the Apple menu: "Shut Down…" and "Log Out…" are never reachable by name.
        for top in AXQuery.elements(bar, kAXChildrenAttribute).dropFirst() {
            guard let title = AXQuery.string(top, kAXTitleAttribute) else { continue }
            for menu in AXQuery.elements(top, kAXChildrenAttribute) { walk.queue.append((menu, [title])) }
        }
        // Breadth first: every top-level menu is read before any submenu, so a big Bookmarks menu cannot hide Window.
        walk.run()
        elements = walk.elements
        return walk.entries
    }

    public func press(_ index: Int) -> Bool {
        guard elements.indices.contains(index) else { return false }
        return AXUIElementPerformAction(elements[index], kAXPressAction as CFString) == .success
    }

    private struct Walk {
        let deadline: ContinuousClock.Instant
        var entries: [MenuEntry] = []
        var elements: [AXUIElement] = []
        var queue: [(menu: AXUIElement, path: [String])] = []

        var exhausted: Bool { entries.count >= AXMenuReader.maxItems || ContinuousClock.now >= deadline }

        mutating func run() {
            var next = 0
            while next < queue.count, !exhausted {
                let (menu, path) = queue[next]
                next += 1
                for item in AXQuery.elements(menu, kAXChildrenAttribute) {
                    if exhausted { return }
                    // Separators have no title.
                    guard let title = AXQuery.string(item, kAXTitleAttribute) else { continue }
                    let enabled = (AXQuery.attr(item, kAXEnabledAttribute) as? Bool) ?? true
                    let subs = AXQuery.elements(item, kAXChildrenAttribute)
                    entries.append(MenuEntry(title: title, path: path, enabled: enabled, hasSubmenu: !subs.isEmpty))
                    elements.append(item)
                    for sub in subs { queue.append((sub, path + [title])) }
                }
            }
        }
    }
}

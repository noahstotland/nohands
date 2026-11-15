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
            for menu in AXQuery.elements(top, kAXChildrenAttribute) { walk.collect(menu, path: [title]) }
        }
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

        var exhausted: Bool { entries.count >= AXMenuReader.maxItems || ContinuousClock.now >= deadline }

        mutating func collect(_ menu: AXUIElement, path: [String]) {
            for item in AXQuery.elements(menu, kAXChildrenAttribute) {
                if exhausted { return }
                // Separators have no title.
                guard let title = AXQuery.string(item, kAXTitleAttribute) else { continue }
                let enabled = (AXQuery.attr(item, kAXEnabledAttribute) as? Bool) ?? true
                entries.append(MenuEntry(title: title, path: path, enabled: enabled))
                elements.append(item)
                for sub in AXQuery.elements(item, kAXChildrenAttribute) { collect(sub, path: path + [title]) }
            }
        }
    }
}

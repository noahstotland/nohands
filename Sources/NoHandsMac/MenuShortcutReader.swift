import Foundation
import ApplicationServices
import NoHandsCore

/// One element of an app's menu bar tree as Accessibility shows it: bar, bar items, menus, items, submenus. A protocol
/// so the walk is tested on a fake tree.
public protocol MenuNode {
    /// Nil for a separator.
    var title: String? { get }
    var enabled: Bool { get }
    var children: [any MenuNode] { get }
    /// `kAXMenuItemCmdChar`, `kAXMenuItemCmdVirtualKey` and `kAXMenuItemCmdModifiers`.
    var commandCharacter: String? { get }
    var virtualKey: Int? { get }
    var modifierMask: Int? { get }
}

/// Reads one app's top-level menu items, with their keyboard shortcuts, for `nohands-cli pack new`. A separate walk
/// from `AXMenuReader`, so the run-time `menu` command, its 200 ms budget and what the task loop sees stay as they are.
public enum MenuShortcutReader {
    public enum ReadError: Error, Equatable { case noMenuBar }

    static let budget: Duration = .seconds(2)
    static let maxItems = 1500

    /// The menu items of the app with `pid`, one level in (`File > Save`, not `File > Open Recent > x`).
    public static func entries(pid: pid_t) throws(ReadError) -> [MenuEntry] {
        try read(pid: pid).entries
    }

    /// Like `entries(pid:)`, and says when the time or item budget cut the read short.
    public static func read(pid: pid_t) throws(ReadError) -> (entries: [MenuEntry], stoppedEarly: Bool) {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        guard let bar = AXQuery.element(appEl, kAXMenuBarAttribute) else { throw .noMenuBar }
        return try read(menuBar: AXMenuNode(bar))
    }

    /// The items in menu bar order, the Apple menu (the first bar item) left out; `noMenuBar` when there are none.
    static func entries(menuBar: some MenuNode, now: () -> ContinuousClock.Instant = { .now }) throws(ReadError) -> [MenuEntry] {
        try read(menuBar: menuBar, now: now).entries
    }

    static func read(menuBar: some MenuNode, now: () -> ContinuousClock.Instant = { .now }) throws(ReadError)
        -> (entries: [MenuEntry], stoppedEarly: Bool) {
        let deadline = now().advanced(by: budget)
        var out: [MenuEntry] = []
        for top in menuBar.children.dropFirst() {
            guard let menuTitle = top.title else { continue }
            for menu in top.children {
                for item in menu.children {
                    guard out.count < maxItems, now() < deadline else { return (out, true) }
                    guard let title = item.title else { continue }   // a separator
                    let shortcut = MenuShortcut.chord(char: item.commandCharacter, virtualKey: item.virtualKey, modifiers: item.modifierMask)
                    out.append(MenuEntry(title: title, path: [menuTitle], enabled: item.enabled, hasSubmenu: !item.children.isEmpty,
                                         shortcut: shortcut))
                }
            }
        }
        guard !out.isEmpty else { throw .noMenuBar }
        return (out, false)
    }
}

private struct AXMenuNode: MenuNode {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }

    var title: String? { AXQuery.string(element, kAXTitleAttribute) }
    var enabled: Bool { (AXQuery.attr(element, kAXEnabledAttribute) as? Bool) ?? true }
    var children: [any MenuNode] { AXQuery.elements(element, kAXChildrenAttribute).map { AXMenuNode($0) } }
    var commandCharacter: String? { AXQuery.attr(element, kAXMenuItemCmdCharAttribute) as? String }
    var virtualKey: Int? { AXQuery.attr(element, kAXMenuItemCmdVirtualKeyAttribute) as? Int }
    var modifierMask: Int? { AXQuery.attr(element, kAXMenuItemCmdModifiersAttribute) as? Int }
}

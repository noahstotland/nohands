import Foundation
import CoreGraphics

/// Keeps a small model from clicking the app's menu bar when it meant the page: a click on a menu-bar item (by
/// number, or by a name that is still unbound) is refused unless the goal is about menus or says the item's own
/// words ("click edit, click copy"). Off while number badges are showing, because the user chose those numbers.
public enum MenuBarGuard {
    private static let menuWords: Set<String> = ["menu", "menus", "menubar"]

    /// Whether the goal allows clicking a menu-bar item called `title`.
    static func allows(title: String, goal: String) -> Bool {
        let words = Set(CommandGrammar.normalize(goal))
        if !menuWords.isDisjoint(with: words) { return true }
        let own = CommandGrammar.normalize(title)
        return !own.isEmpty && own.allSatisfy(words.contains)
    }

    /// A menu-bar item standing for `title`, so `LabelAssigner.find` can match a click's name against the titles.
    static func items(_ titles: [String]) -> [UIElementInfo] {
        titles.map { UIElementInfo(id: 0, frame: .zero, title: $0, role: "AXMenuBarItem") }
    }

    /// A failure message when a click lands on a menu-bar item the goal does not allow; nil when allowed.
    public static func blocked(_ actions: [Action], labels: [Int: UIElementInfo], menuBarTitles: [String], goal: String,
                               badgesShowing: Bool) -> String? {
        guard !badgesShowing else { return nil }
        let bar = items(menuBarTitles)
        for case .click(let target, _, _) in actions {
            switch target {
            case .label(let n):
                if let e = labels[n], LabelAssigner.isMenuBarItem(e), !allows(title: e.title, goal: goal) {
                    return "label \(n) is the \"\(e.title)\" menu bar item, not a page element"
                }
            case .element(let name):
                if let e = LabelAssigner.find(named: name, in: bar), !allows(title: e.title, goal: goal) {
                    return "\"\(e.title)\" is a menu bar item, not a page element"
                }
            default:
                continue
            }
        }
        return nil
    }
}

/// Points a named click at the element list the model was shown. Without it, "click Edit" resolves against a fresh
/// walk whose first match is the menu bar, even when the page has its own Edit button.
public enum ElementNames {
    /// Rewrites the step's first action when it is a click by name that equals (trimmed, case-insensitive) the title
    /// of a non-menu-bar element in `labels`, lowest number first. Later actions keep their names: a number resolves
    /// against the snapshot from before the step, which an earlier action may have changed. A name that is a menu-bar
    /// item the goal allows ("click edit, click copy") is left to the menu bar.
    public static func bind(_ actions: [Action], labels: [Int: UIElementInfo], menuBarTitles: [String], goal: String) -> [Action] {
        guard case .click(.element(let name), let button, let count)? = actions.first else { return actions }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return actions }
        if let bar = LabelAssigner.find(named: name, in: MenuBarGuard.items(menuBarTitles)),
           MenuBarGuard.allows(title: bar.title, goal: goal) { return actions }
        for n in labels.keys.sorted() {
            guard let e = labels[n], !LabelAssigner.isMenuBarItem(e),
                  e.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted else { continue }
            var bound = actions
            bound[0] = .click(.label(n), button: button, count: count)
            return bound
        }
        return actions
    }
}

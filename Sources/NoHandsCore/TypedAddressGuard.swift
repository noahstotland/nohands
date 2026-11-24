import Foundation

/// A small model often types a URL where it should open one. When a step's `type_text` is a whole web address, it
/// becomes an `open_url` (an ordinary one, so it can only be `http(s)` and the other guards still see it), and a
/// bare Return right after it is dropped. Left alone when the user asked to enter text, or when the step first set
/// up a place to type (`open_app`, `command-l`).
public enum TypedAddressGuard {
    /// Goal words that show the user wants text entered, so a typed address is the text they asked for.
    private static let textEntryWords: Set<String> = [
        "type", "types", "typing", "typed", "write", "writes", "writing", "enter", "entering", "paste", "pasting",
        "dictate", "insert", "fill", "send", "sending", "reply", "post", "comment", "message", "email", "text",
    ]

    public static func rewrite(_ actions: [Action], goal: String) -> [Action] {
        guard textEntryWords.isDisjoint(with: Set(CommandGrammar.normalize(goal))) else { return actions }
        var result: [Action] = []
        var setUp = false
        var justConverted = false
        for action in actions {
            let afterConversion = justConverted
            justConverted = false
            switch action {
            case .openApp:
                setUp = true
            case .pressKey(let chord):
                if chord.key == .l, chord.modifiers == [.command] { setUp = true }
                if afterConversion, chord.key == .return, chord.modifiers.isEmpty { continue }
            case .typeText(let text):
                if !setUp, let url = WebAddress.typedAddress(text) {
                    result.append(.openURL(url, app: nil))
                    justConverted = true
                    continue
                }
            default:
                break
            }
            result.append(action)
        }
        return result
    }
}

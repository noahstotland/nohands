import Foundation

/// What a text-editing voice command works on. Grammar only: the model has no kind for these.
public enum TextUnit: String, Codable, Sendable { case word, line, sentence, paragraph }
public enum CaretPlace: String, Codable, Sendable { case lineStart, lineEnd, documentStart, documentEnd }
public enum CaseChange: String, Codable, Sendable { case capitalize, upper, lower }

/// A spoken edit of the focused text field ("select the last sentence", "replace meeting with call"). Phrases keep the
/// speaker's own words; the field's text is only ever read by Core's range maths and never stored here.
public enum TextEdit: Equatable, Codable, Sendable {
    case select(TextUnit, last: Bool), delete(TextUnit, last: Bool)
    case selectPhrase(String), deletePhrase(String), replace(String, with: String)
    case caretBefore(String), caretAfter(String), caret(CaretPlace)
    case changeCase(CaseChange)

    /// True when the edit looks the text up by words the speaker said (so it needs a readable field).
    public var targetsPhrase: Bool {
        switch self {
        case .selectPhrase, .deletePhrase, .replace, .caretBefore, .caretAfter: true
        case .select, .delete, .caret, .changeCase: false
        }
    }
}

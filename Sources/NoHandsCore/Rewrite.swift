import Foundation

/// A preset rewrite ("make it shorter"). Raw values are what the log records as the instruction kind.
public enum RewriteStyle: String, Codable, Sendable {
    case shorter, longer, clearer, simpler, concise, formal, casual, polite, professional, friendly, grammar

    /// The fixed English instruction the request carries.
    public var sentence: String {
        switch self {
        case .shorter: "Make it shorter."
        case .longer: "Make it longer."
        case .clearer: "Rewrite it to read more clearly."
        case .simpler: "Make it simpler."
        case .concise: "Make it more concise."
        case .formal: "Make it more formal."
        case .casual: "Make it more casual."
        case .polite: "Make it more polite."
        case .professional: "Make it more professional."
        case .friendly: "Make it friendlier."
        case .grammar: "Fix spelling, grammar and punctuation. Change nothing else."
        }
    }
}

/// What to do to the selected text. Grammar only, like `Action.editText`: the model has no kind for it.
public enum RewriteInstruction: Equatable, Codable, Sendable {
    case style(RewriteStyle)
    /// `language` is 1 to 3 words, letters only, as the speaker said it.
    case translate(language: String)
    /// The speaker's own words ("as a list", "in the first person").
    case custom(String)

    /// The English instruction the request carries.
    public var sentence: String {
        switch self {
        case .style(let s): s.sentence
        case .translate(let language): "Translate it into \(language)."
        case .custom(let words): "Rewrite it: \(words)."
        }
    }

    /// Payload-free kind for logs: never the language or the speaker's words.
    public var kind: String {
        switch self {
        case .style(let s): s.rawValue
        case .translate: "translate"
        case .custom: "custom"
        }
    }
}

/// Why a rewrite did not happen, with the HUD text (what the user can do next). Never carries the text itself.
public enum RewriteError: Error, Equatable, Sendable {
    case nothingToRewrite, subjectTooLong, noAnswer, answerTooLong

    public var message: String {
        switch self {
        case .nothingToRewrite: "nothing to rewrite: select some text"
        case .subjectTooLong: "too long to rewrite: select under 2,000 characters"
        case .noAnswer: "the model gave no text"
        case .answerTooLong: "rewrite too long: try a shorter selection"
        }
    }
}

/// What a rewrite works on: the selection, else the last sentence that ends at or before the caret.
public struct RewriteSubject: Equatable, Sendable {
    public static let maxCharacters = 2000

    public let span: TextSpan
    public let text: String

    /// `selection` is the field's UTF-16 selection (empty: the caret). Throws before anything is sent.
    public static func pick(in value: String, selection: TextSpan) throws(RewriteError) -> RewriteSubject {
        let length = (value as NSString).length
        let span: TextSpan
        if selection.length > 0 {
            span = selection
        } else if let last = TextRanges.unit(.sentence, last: true, in: value, caret: selection.location) {
            span = last
        } else {
            throw .nothingToRewrite
        }
        guard span.location >= 0, span.end <= length else { throw .nothingToRewrite }
        let text = (value as NSString).substring(with: NSRange(location: span.location, length: span.length))
        guard text.contains(where: { !$0.isWhitespace }) else { throw .nothingToRewrite }
        guard text.count <= maxCharacters else { throw .subjectTooLong }
        return RewriteSubject(span: span, text: text)
    }
}

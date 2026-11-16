import Foundation

/// A folder that opens by name ("open the downloads folder"). The paths come from this table, not from input.
public enum StandardFolder: String, CaseIterable, Codable, Sendable {
    case desktop, documents, downloads, pictures, music, movies, home, applications, trash

    /// How each is said, singular and plural; `apps` and `home` as well.
    private static let spoken: [String: StandardFolder] = [
        "desktop": .desktop, "documents": .documents, "document": .documents, "downloads": .downloads,
        "download": .downloads, "pictures": .pictures, "picture": .pictures, "music": .music, "movies": .movies,
        "movie": .movies, "home": .home, "applications": .applications, "application": .applications,
        "apps": .applications, "trash": .trash,
    ]

    public init?(spoken words: [String]) {
        guard words.count == 1, let folder = Self.spoken[words[0]] else { return nil }
        self = folder
    }

    /// The folder's path for the home folder `home`.
    public func path(home: String) -> String {
        switch self {
        case .applications: "/Applications"
        case .home: home
        case .trash: home + "/.Trash"
        default: home + "/" + rawValue.capitalized
        }
    }
}

/// What kind of file a phrase asks for. `file` is anything that is not a folder.
public enum FileKind: String, CaseIterable, Codable, Sendable {
    case file, document, spreadsheet, presentation, pdf, folder, keynote, pages, numbers, word, excel, powerpoint

    /// The kind words "my last <kind>" takes.
    static let recentWords: [String: FileKind] = [
        "file": .file, "document": .document, "spreadsheet": .spreadsheet, "presentation": .presentation, "pdf": .pdf,
        "keynote": .keynote, "pages": .pages, "numbers": .numbers, "word": .word, "excel": .excel, "powerpoint": .powerpoint,
    ]

    /// The kind words that end a name ("the budget spreadsheet").
    static let suffixWords: [String: FileKind] = [
        "file": .file, "document": .document, "spreadsheet": .spreadsheet, "presentation": .presentation, "pdf": .pdf,
        "folder": .folder,
    ]

    /// Spotlight content types the kind matches; nil is any file that is not a folder.
    public var contentTypes: [String]? {
        switch self {
        case .file: nil
        case .folder: ["public.folder"]
        case .document: ["public.composite-content", "public.text"]
        case .spreadsheet: Self.sheets + ["com.apple.iwork.numbers.sffnumbers", "public.comma-separated-values-text"]
        case .presentation: Self.slides + ["com.apple.iwork.keynote.sffkey"]
        case .pdf: ["com.adobe.pdf"]
        case .keynote: ["com.apple.iwork.keynote.sffkey", "com.apple.iwork.keynote.key"]
        case .pages: ["com.apple.iwork.pages.sffpages", "com.apple.iwork.pages.pages"]
        case .numbers: ["com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers"]
        case .word: ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc"]
        case .excel: Self.sheets
        case .powerpoint: Self.slides
        }
    }
    private static let sheets = ["org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls"]
    private static let slides = ["org.openxmlformats.presentationml.presentation", "com.microsoft.powerpoint.ppt"]
}

/// What to open: a standard folder, a file or folder found by the words in its name, or the newest file of a kind.
/// Built by the grammar and by the decoder alike, so one executor path runs both. Never a path.
public enum FileRequest: Equatable, Codable, Sendable {
    case folder(StandardFolder)
    case named(String, kind: FileKind)
    case recent(FileKind)

    /// What a model's words may be: 1 to 100 characters with no path, home or drive characters and no control character.
    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 100
            && !trimmed.unicodeScalars.contains { "/\\~:".unicodeScalars.contains($0) || $0.properties.generalCategory == .control }
    }

    /// The name words, folded and split.
    public static func words(_ name: String) -> [String] {
        FileRank.fold(name).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The action for the command log and route memory: names no hit, and not the spoken words either.
    public var logName: String {
        switch self {
        case .folder(let f): "open folder \(f.rawValue)"
        case .named: "open file"
        case .recent(let k): "open recent \(k.rawValue)"
        }
    }
}

/// A Spotlight question: every word in the display name, of this kind; `newestFirst` ranks by last use for "my last".
public struct FileQuery: Equatable, Sendable {
    public var words: [String]
    public var kind: FileKind
    public var newestFirst: Bool
    public init(words: [String], kind: FileKind, newestFirst: Bool = false) {
        self.words = words; self.kind = kind; self.newestFirst = newestFirst
    }
}

/// One thing Spotlight found.
public struct FileHit: Equatable, Sendable {
    public var path: String
    public var name: String
    public var lastUsed: Date?
    public var modified: Date?
    public init(path: String, name: String, lastUsed: Date? = nil, modified: Date? = nil) {
        self.path = path; self.name = name; self.lastUsed = lastUsed; self.modified = modified
    }

    /// The parent folder's name, for the list. Never the full path.
    public var parent: String {
        (((path as NSString).deletingLastPathComponent) as NSString).lastPathComponent
    }
}

public enum FileRank {
    /// Lower-cased, accents removed.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether every word is in the name, ignoring case and accents.
    public static func matches(_ name: String, words: [String]) -> Bool {
        let folded = fold(name)
        return words.allSatisfy { folded.contains(fold($0)) }
    }

    /// An exact name first (no extension, ignoring case and accents), then the most recently used (last-used date,
    /// else modified date; none is last), then the shorter name, then the path, so the order is stable.
    public static func order(_ hits: [FileHit], words: [String]) -> [FileHit] {
        let spoken = fold(words.joined(separator: " "))
        func exact(_ h: FileHit) -> Bool {
            !spoken.isEmpty && (fold(h.name) == spoken || fold((h.name as NSString).deletingPathExtension) == spoken)
        }
        func date(_ h: FileHit) -> Date { h.lastUsed ?? h.modified ?? .distantPast }
        return hits.sorted { a, b in
            if exact(a) != exact(b) { return exact(a) }
            if date(a) != date(b) { return date(a) > date(b) }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.path < b.path
        }
    }
}

/// What the Mac side read about one hit. The guard decides over these facts and touches no disk itself.
public struct FileFacts: Equatable, Sendable {
    /// The home folder, resolved, and as the hit's path spells it.
    public var home: String
    public var foundHome: String
    /// The hit's path as found and with every symlink resolved.
    public var found: String
    public var resolved: String
    public var hidden = false
    public var isDirectory = false
    public var isRegularFile = false
    public var isPackage = false
    public var conformsToExecutable = false
    public var conformsToContent = false
    public var hasExecuteBit = false
    public var exists = true
    public var readable = true
    public var fileExtension = ""
    public init(home: String, foundHome: String? = nil, found: String, resolved: String? = nil) {
        self.home = home; self.foundHome = foundHome ?? home; self.found = found; self.resolved = resolved ?? found
    }
}

public enum FileOpenDecision: Equatable, Sendable {
    case allow
    case refuse(FileRefusal)
}

public enum FileRefusal: Equatable, Sendable {
    /// Outside home, a dot path, or Library.
    case outside
    /// It can run as a program, or installs or opens something else.
    case runnable
    case gone

    /// The row's text. The name is shown only for `runnable`: that hit was on screen already.
    public func message(name: String) -> String {
        switch self {
        case .outside: "won't open that file"
        case .runnable: "won't open \(name)\(Self.runnableSuffix)"
        case .gone: "can't read that file"
        }
    }

    private static let runnableSuffix = ": it can run as a program"

    /// A failure as the logs keep it: a refusal names no file.
    public static func redacted(_ failure: String) -> String {
        failure.hasPrefix("won't open ") && failure.hasSuffix(runnableSuffix) ? FileRefusal.runnable.message(name: "a file") : failure
    }
}

/// Which paths may open by voice (NH-58). The five rules are in the spec; each is a case in the tests.
public enum FileOpenGuard {
    public static let deniedExtensions: Set<String> = [
        "app", "command", "tool", "sh", "bash", "zsh", "csh", "ksh", "fish", "py", "pl", "rb", "js", "jar", "terminal",
        "workflow", "action", "pkg", "mpkg", "dmg", "mobileconfig", "prefpane", "saver", "kext", "plugin", "bundle",
        "qlgenerator", "scpt", "scptd", "applescript", "osascript", "webloc", "inetloc", "fileloc", "url", "shortcut",
    ]

    private static func parts(_ path: String) -> [String] { path.split(separator: "/").map(String.init) }

    /// The components of `path` below `base`, or nil when it is not strictly below it. Whole components, so
    /// `/Users/noah2` is not under `/Users/noah`.
    static func below(_ path: String, _ base: String) -> [String]? {
        let p = parts(path), b = parts(base)
        return p.count > b.count && Array(p[..<b.count]) == b ? Array(p[b.count...]) : nil
    }

    /// Rules 2 and 3 on one path spelling: a dot component, or Library or `.config/nohands` (named, as a second lock).
    private static func isHiddenOrLibrary(_ rest: [String]) -> Bool {
        if rest.contains(where: { $0.hasPrefix(".") }) { return true }
        let lower = rest.map { $0.lowercased() }
        return lower.first == "library" || lower.starts(with: [".config", "nohands"])
    }

    /// Whether a path found by a search may be listed at all: below home, no dot part, not Library. The source drops the
    /// rest before ranking.
    public static func isListable(_ path: String, home: String) -> Bool {
        guard let rest = below(path, home) else { return false }
        return !isHiddenOrLibrary(rest)
    }

    public static func decide(_ f: FileFacts) -> FileOpenDecision {
        // 1. Resolved inside home. 2 and 3. No dot part and no Library, as found and as resolved.
        guard let resolved = below(f.resolved, f.home), !isHiddenOrLibrary(resolved), !f.hidden else { return .refuse(.outside) }
        if let found = below(f.found, f.foundHome), isHiddenOrLibrary(found) { return .refuse(.outside) }
        // 4. Never executable.
        let ext = f.fileExtension.lowercased()
        if f.conformsToExecutable || deniedExtensions.contains(ext) || (f.isPackage && !f.conformsToContent)
            || (f.isRegularFile && f.hasExecuteBit) { return .refuse(.runnable) }
        // 5. Exists and is readable.
        return f.exists && f.readable ? .allow : .refuse(.gone)
    }
}

/// The list "open file budget" shows when several files match, and how the next words answer it. Pure; the pipeline
/// owns the timer and the rows.
public struct FilePick: Equatable, Sendable {
    public static let maxRows = 6
    public static let timeout: Duration = .seconds(30)

    public enum Reply: Equatable, Sendable {
        /// A stop phrase: close the list.
        case cancel
        /// The index (from 0) of the hit to open.
        case open(Int)
        /// A number outside the list: say it again, the list stays.
        case retry
        /// Anything else: close the list and route the words as usual.
        case passThrough
    }

    public let hits: [FileHit]
    /// There were more than `maxRows`.
    public let more: Bool
    public let rowID: Int
    public let deadline: ContinuousClock.Instant

    /// `ranked` is every allowed hit in rank order.
    public init(ranked: [FileHit], rowID: Int, now: ContinuousClock.Instant = .now, timeout: Duration = FilePick.timeout) {
        hits = Array(ranked.prefix(Self.maxRows))
        more = ranked.count > Self.maxRows
        self.rowID = rowID
        deadline = now.advanced(by: timeout)
    }

    private static let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6]

    /// A stop phrase is checked first, so it is never read as a number. `transcript` has its attention word removed.
    public func reply(_ transcript: String) -> Reply {
        if StopWords.isStop(transcript) { return .cancel }
        var words = CommandGrammar.normalize(transcript)[...]
        while let lead = words.first, ["open", "number", "the"].contains(lead) { words = words.dropFirst() }
        let number: Int?
        if let n = words.first.flatMap({ Self.ordinals[$0] }), words.count == 1 || (words.count == 2 && ["one", "file"].contains(words[words.startIndex + 1])) {
            number = n
        } else {
            number = NumberWords.parse(Array(words))
        }
        guard let n = number else { return .passThrough }
        return n >= 1 && n <= hits.count ? .open(n - 1) : .retry
    }

    /// The prompt row's text while the list shows.
    public var prompt: String { "say 1 to \(hits.count), or cancel" + (more ? " (more: say more words)" : "") }
    public var retryPrompt: String { "say 1 to \(hits.count), or cancel" }

    /// The numbered rows for the corner panel: "1 Budget 2026.xlsx · Documents".
    public var trail: TaskTrail {
        var trail = TaskTrail(maxSteps: hits.count, choices: true)
        for (i, hit) in hits.enumerated() { trail.begin(number: i + 1, intent: "\(i + 1) \(hit.name) · \(hit.parent)") }
        return trail
    }
}

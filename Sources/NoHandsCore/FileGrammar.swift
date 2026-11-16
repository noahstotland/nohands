import Foundation

extension CommandGrammar {
    private static let articles: Set<String> = ["the", "my"]
    private static let recentLeads: [[String]] = [["last"], ["latest"], ["most", "recent"]]

    /// The words after "open" as a file phrase, or nil for anything else (an app, a site, a compound request).
    ///
    ///     open the downloads folder, open trash          a standard folder
    ///     open the reports folder                        a folder by name (needs "the" or "my")
    ///     open file budget, open the budget file         a file by name
    ///     open the budget spreadsheet                    the same, of a kind (needs "the" or "my")
    ///     open my last keynote                           the newest file of a kind
    ///
    /// A bare name stays an app ("open music", "open home"): only `trash` has a bare form.
    static func parseOpenFile(_ rest: [String]) -> [Action]? {
        var body = rest[...]
        let article = body.first.map(articles.contains) ?? false
        if article { body = body.dropFirst() }
        guard !body.isEmpty else { return nil }
        if Array(body) == ["trash"] { return [.openFile(.folder(.trash))] }

        if article, let lead = recentLeads.first(where: { body.starts(with: $0) }) {
            var kind = Array(body.dropFirst(lead.count))
            if kind.count == 2, ["file", "document"].contains(kind[1]), !["file", "document"].contains(kind[0]) { kind.removeLast() }
            return kind.count == 1 ? FileKind.recentWords[kind[0]].map { [.openFile(.recent($0))] } : nil
        }

        // The name and its kind: "file <words>", or "<words> folder|file|document|spreadsheet|presentation|pdf".
        let name: [String], kind: FileKind
        if !article, body.first == "file", body.count > 1 {
            name = Array(body.dropFirst()); kind = .file
        } else if body.count > 1, let last = body.last, let suffix = FileKind.suffixWords[last] {
            name = Array(body.dropLast()); kind = suffix
            if kind == .folder, let folder = StandardFolder(spoken: name) { return [.openFile(.folder(folder))] }
            guard article else { return nil }
        } else {
            return nil
        }
        // A compound request ("open the budget file and print it") is the model's.
        guard compoundMarkers.isDisjoint(with: name) else { return nil }
        let words = name.joined(separator: " ")
        return FileRequest.isValidName(words) ? [.openFile(.named(words, kind: kind))] : nil
    }
}

import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

/// A source and an opener that touch no disk: it finds `hits`, refuses the paths in `runnable`, and records what opened.
@MainActor private final class FakeFiles: FileSource, FileOpening {
    let home = "/Users/noah"
    var hits: [FileHit] = []
    var runnable: Set<String> = []
    var queries: [FileQuery] = []
    var opened: [String] = []
    func search(_ query: FileQuery) async -> [FileHit] { queries.append(query); return hits }
    func facts(forPath path: String) -> FileFacts {
        var f = FileFacts(home: home, found: path)
        f.isRegularFile = true; f.conformsToContent = true; f.conformsToExecutable = runnable.contains(path)
        return f
    }
    func open(path: String, inFinder: Bool) async -> Bool { opened.append((inFinder ? "finder " : "") + path); return true }
}

private func file(_ name: String, in dir: String = "Documents") -> FileHit { FileHit(path: "/Users/noah/\(dir)/\(name)", name: name) }

@MainActor private func executor(_ files: FakeFiles) -> ActionExecutor {
    ActionExecutor(input: FakeInput(), ax: FakeElements(), overlay: FakeOverlay(), config: AppConfig(), files: files, fileOpener: files)
}

@MainActor @Test func openFileOpensOneListsSeveralAndFailsWithWordsThatNameNoFile() async {
    var a = file("Budget 2026.xlsx"), b = file("Budget notes.txt", in: "Desktop"), script = file("budget.sh")
    a.lastUsed = Date()   // the newest of the two
    // (what the source finds, the request, the context, the failure, what opened, whether a list is offered)
    let table: [([FileHit], FileRequest, FileContext, String?, [String], Bool)] = [
        ([a], .named("budget", kind: .file), .spoken, nil, [a.path], false),
        ([a, b], .named("budget", kind: .file), .spoken, nil, [], true),
        ([a, b], .named("budget", kind: .file), .macro, "several files match: say open file budget", [], false),
        ([a, b], .named("budget", kind: .file), .model, "several files match: ask the user to say open file budget", [], false),
        ([], .named("budget", kind: .file), .spoken, "no file called \"budget\"", [], false),
        ([], .named("budget", kind: .folder), .macro, "no folder called \"budget\"", [], false),
        ([], .named("budget", kind: .file), .model, "no file matched", [], false),
        ([script], .named("budget", kind: .file), .spoken, "won't open budget.sh: it can run as a program", [], false),
        ([script], .named("budget", kind: .file), .model, "won't open a file: it can run as a program", [], false),
        ([script], .named("budget", kind: .file), .macro, "won't open a file: it can run as a program", [], false),
        ([script, a], .named("budget", kind: .file), .spoken, nil, [a.path], false),
        ([a, b], .recent(.spreadsheet), .spoken, nil, [a.path], false),
        ([], .recent(.keynote), .spoken, "no recent keynote", [], false),
        ([], .folder(.downloads), .spoken, nil, ["finder /Users/noah/Downloads"], false),
    ]
    for (hits, request, context, failure, opened, offered) in table {
        let files = FakeFiles()
        files.hits = hits; files.runnable = [script.path]
        let x = executor(files)
        #expect(await x.execute([.openFile(request)], files: context) == failure, "\(request) \(context)")
        #expect(files.opened == opened, "\(request) \(context)")
        #expect((x.takeFileOffer() != nil) == offered, "\(request) \(context)")
    }
    // The model is told what happened and no name; the list never reaches it.
    let files = FakeFiles(); files.hits = [file("Q3 plan.pdf")]
    let x = executor(files)
    _ = await x.execute([.openFile(.named("plan", kind: .pdf))])
    #expect(x.takeReadings() == ["opened a file"])
    #expect(files.queries == [FileQuery(words: ["plan"], kind: .pdf)])
}

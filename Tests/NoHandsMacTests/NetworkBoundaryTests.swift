import Foundation
import Testing

private let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources")

/// Every Swift file under Sources (path relative to Sources) and its text.
private func swiftFiles() -> [(path: String, text: String)] {
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
    return files.filter { $0.pathExtension == "swift" }.map {
        (String($0.path.dropFirst(sources.path.count + 1)), (try? String(contentsOf: $0, encoding: .utf8)) ?? "")
    }
}

/// Where a pack download can start, and which files may make any network call at all. A new caller fails this test
/// until someone adds it here on purpose. It is a text check: it guards against accidents, review covers the rest.
@Test func theNetworkIsReachedOnlyFromTheFilesThatMeanTo() {
    let files = swiftFiles()
    #expect(files.count > 50)
    func mentioning(_ words: [String], in list: [(path: String, text: String)]) -> Set<String> {
        Set(list.filter { file in words.contains { file.text.contains($0) } }.map(\.path))
    }
    let callers = mentioning(["PackFetcher"], in: files)
    #expect(callers.contains("NoHandsMac/PackFetcher.swift") && callers.isSubset(of: [
        "NoHandsMac/PackFetcher.swift", "NoHands/PackBrowser.swift", "NoHands/AppDelegate.swift",
        "nohands-cli/PackCommands.swift", "nohands-cli/RegistryCommands.swift"]), "PackFetcher callers: \(callers)")
    let commandPath = files.filter { f in
        ["VoicePipeline.swift", "CommandGrammar.swift", "ModeMachine.swift", "TaskRunner.swift"].contains { f.path.hasSuffix("/" + $0) } || f.path.contains("/ActionExecutor")
    }
    #expect(commandPath.count >= 8)
    #expect(mentioning(["PackFetcher", "URLSession", "URLRequest", "RegistryIndex", "PackRegistry"], in: commandPath).isEmpty, "command path")
    let core = files.filter { $0.path.hasPrefix("NoHandsCore/") }
    #expect(mentioning(["URLSession", "URLRequest", "NWConnection", "import Network", "CFNetwork"], in: core).isEmpty, "NoHandsCore")
    #expect(mentioning(["URLSession"], in: files) == ["NoHandsMac/ClaudeConnectionCheck.swift", "NoHandsMac/OllamaClient.swift", "NoHandsMac/TextRewriter.swift",
                                                       "NoHandsMac/OllamaIntentResolver.swift", "NoHandsMac/IntentHTTP.swift", "NoHandsMac/ClaudeIntentResolver.swift",
                                                       "NoHandsMac/PackFetcher.swift"], "URLSession users")
}

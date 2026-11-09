import Testing
import Foundation
@testable import NoHandsCore

private func json(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }

@Test func planRequestsSendOnlyTheGoalAndKeepTheModelWarm() throws {
    let goal = "put on the latest\nmaple video"
    let step = StepRequest(oneShot: goal, context: IntentContext(frontmostApp: "Finder", mode: .command, labeledElements: []))
    // Ollama: the same model, context size and keep-alive as a task step, or Ollama reloads the model.
    let ollama = OllamaRequestBuilder(model: "qwen-test")
    let plan = json(ollama.planBody(goal: goal)), task = json(try ollama.body(request: step))
    for key in ["model", "keep_alive", "stream"] { #expect(plan[key] as? NSObject == task[key] as? NSObject, "\(key)") }
    #expect((plan["options"] as? NSDictionary) == (task["options"] as? NSDictionary))
    let messages = try #require(plan["messages"] as? [[String: String]])
    #expect(messages.last == ["role": "user", "content": "Goal: put on the latest maple video"])
    #expect(messages.first?["role"] == "system")
    // Claude: the cached system block holds rules and examples; the user turn is the goal and nothing else.
    let claude = json(try ClaudeRequestBuilder(model: "claude-test", effort: "low").planBody(goal: goal))
    #expect(claude["model"] as? String == "claude-test")
    let system = try #require((claude["system"] as? [[String: Any]])?.first)
    #expect((system["cache_control"] as? [String: String])?["type"] == "ephemeral")
    #expect((system["text"] as? String)?.contains("Examples:") == true)
    let user = try #require(claude["messages"] as? [[String: Any]])
    #expect((user.first?["content"] as? [[String: String]])?.first?["text"] == "Goal: put on the latest maple video")
    for body in [ollama.planBody(goal: goal), try ClaudeRequestBuilder(model: "m").planBody(goal: goal)] {
        let text = String(decoding: body, as: UTF8.self)
        for leak in ["Visible elements", "Window:", "URL:", "Tabs:"] { #expect(!text.contains(leak), "\(leak)") }
    }
}

@Test func planPromptNamesNoSiteAndItsExamplesCannotRun() throws {
    let banned = WebAddress.knownSites.keys.filter { $0.count > 2 } + ["channel", "handle", "playlist", "subscribe"]
    func names(_ word: String, in text: String) -> Bool {
        let spaced = " " + text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") + " "
        return spaced.contains(" \(word) ")
    }
    for word in banned { #expect(!names(word, in: PlanQuestion.systemPrompt), "prompt names \(word)") }
    var nulls = 0
    for (goal, answer) in PlanQuestion.examples {
        for word in banned { #expect(!names(word, in: goal + " " + answer), "example names \(word)") }
        guard let plan = TaskPlan.decode(fromPayloadText: answer) else { nulls += 1; continue }
        // Every example decodes, and copying it verbatim is refused: each address is on the reserved `.example`.
        let urls = plan.steps.compactMap(\.url)
        #expect(!urls.isEmpty)
        for u in urls { #expect(URL(string: u)?.host?.hasSuffix(".example") == true, "\(u)") }
        #expect(plan.validated(goal: goal) == nil, "\(goal)")
    }
    #expect(nulls == 2)
}

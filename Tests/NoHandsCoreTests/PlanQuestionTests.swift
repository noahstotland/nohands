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

/// Every `properties` object in the schema, with its `required` list.
private func objects(in node: Any) -> [(properties: Set<String>, required: Set<String>)] {
    var found: [(Set<String>, Set<String>)] = []
    if let d = node as? [String: Any] {
        if let props = d["properties"] as? [String: Any] {
            found.append((Set(props.keys), Set(d["required"] as? [String] ?? [])))
        }
        for v in d.values { found += objects(in: v) }
    } else if let a = node as? [Any] {
        for v in a { found += objects(in: v) }
    }
    return found
}

@Test func planSchemaOffersOnlyListedSitesAndHasNoOptionalProperties() throws {
    let schema = PlanQuestion.orderedSchema.foundationObject
    func site(_ n: Any) -> [String]? {
        if let d = n as? [String: Any] {
            if let s = (d["properties"] as? [String: Any])?["site"] as? [String: Any] { return s["enum"] as? [String] }
            return d.values.lazy.compactMap(site).first
        }
        if let a = n as? [Any] { return a.lazy.compactMap(site).first }
        return nil
    }
    // The enum is the site list plus "" (a step with no site): constrained decoding cannot write an address.
    #expect(site(schema) == [""] + SiteSearch.siteNames)
    // Claude refuses a schema with many optional properties: all of them are required.
    let all = objects(in: schema)
    #expect(all.count == 3)
    for o in all { #expect(o.properties == o.required) }
}

@Test func planPromptListsTheSitesAndNamesNoFlow() throws {
    for site in SiteSearch.siteNames { #expect(PlanQuestion.systemPrompt.contains(site), "\(site)") }
    // Outside the site list the prompt and its examples name no site flow, and carry no address.
    let listless = PlanQuestion.systemPrompt.replacingOccurrences(of: SiteSearch.siteNames.joined(separator: ", "), with: "")
    let banned = ["youtube", "channel", "handle", "playlist", "subscribe", "http", "://"]
    let text = (listless + PlanQuestion.examples.map { $0.goal + $0.answer }.joined()).lowercased()
    for word in banned { #expect(!text.contains(word), "names \(word)") }
    var nulls = 0
    for (goal, answer) in PlanQuestion.examples {
        guard let plan = TaskPlan.decode(fromPayloadText: answer) else { nulls += 1; continue }
        // An example is a plan that passes the rules for its own goal, on sites from the list.
        #expect(plan.validated(goal: goal) != nil, "\(goal)")
    }
    #expect(nulls == 2)
}

import Foundation

/// Fixed route text for the sites people use most, added to the user message when the goal names the site or the
/// page is on it. Written by NoHands: no window or element title is ever read for matching and no page text goes in.
public enum SitePlaybooks {
    struct Playbook: Sendable {
        let name: String
        /// Words that name the site in a goal; a phrase matches as consecutive whole words.
        let phrases: [[String]]
        /// A phrase followed by one of these is another product ("google chrome"), not the site.
        let notFollowedBy: Set<String>
        /// Page hosts, compared exactly (lower-cased). `SiteSearch.templateKey(forHost:)` is not used: its subdomain
        /// rule would put Gmail and Docs on Google.
        let hosts: Set<String>
        /// When the route was fetched, and how far the check went.
        let checked: String
        let lines: [String]
    }

    static let table: [Playbook] = [
        Playbook(
            name: "YouTube", phrases: [["youtube"], ["you", "tube"]], notFollowedBy: [],
            hosts: ["www.youtube.com", "youtube.com", "m.youtube.com"], checked: "2026-11-15 (results pages fetched)",
            lines: [
                "Latest video of a channel: do not guess a @handle unless the request or the screen shows it. open_url",
                "https://www.youtube.com/results?search_query=<name, words joined by +>&sp=EgIQAg%253D%253D (channels only), then",
                "wait 1500. Click the first channel result, then its Videos tab, then the first video, which is the newest.",
                "Play a video or song: open_url https://www.youtube.com/results?search_query=<words joined by +>, then wait 1500.",
                "Click the first video result that is not marked Sponsored.",
                "Player keys, once the video page is open: k play or pause, f full screen, m mute.",
            ]),
        Playbook(
            name: "Google", phrases: [["google"]],
            notFollowedBy: ["chrome", "docs", "drive", "maps", "calendar", "sheets", "slides", "meet", "photos", "earth", "mail"],
            hosts: ["www.google.com", "google.com"], checked: "2026-11-15 (URL only; plain HTTP gets a JavaScript page)",
            lines: [
                "Search the web: open_url https://www.google.com/search?q=<words joined by +>, then wait 1500.",
                "Click the result that best fits the goal.",
            ]),
        Playbook(
            name: "Wikipedia", phrases: [["wikipedia"]], notFollowedBy: [],
            hosts: ["en.wikipedia.org", "www.wikipedia.org", "wikipedia.org"], checked: "2026-11-15 (results pages fetched)",
            lines: [
                "Look something up: open_url https://en.wikipedia.org/w/index.php?search=<words joined by +>, then wait 1500.",
                "An exact article title opens that article; otherwise click the first result.",
            ]),
        Playbook(
            name: "Amazon", phrases: [["amazon"]], notFollowedBy: ["prime", "music", "kindle", "web"],
            hosts: ["www.amazon.com", "amazon.com"], checked: "2026-11-15 (results page fetched)",
            lines: [
                "Find a product: open_url https://www.amazon.com/s?k=<words joined by +>, then wait 1500.",
                "Click the first result that is not marked Sponsored.",
            ]),
        Playbook(
            name: "Reddit", phrases: [["reddit"]], notFollowedBy: [],
            hosts: ["www.reddit.com", "old.reddit.com", "reddit.com"], checked: "2026-11-15 (URL only; plain HTTP gets a JavaScript page)",
            lines: [
                "Search Reddit: open_url https://www.reddit.com/search/?q=<words joined by +>, then wait 1500.",
                "Click the post that best fits the goal.",
            ]),
    ]

    /// The YouTube page hosts, for the media commands to tell a YouTube page from any other.
    static let youTubeHosts: Set<String> = table.first { $0.name == "YouTube" }?.hosts ?? []

    /// The playbooks whose site the goal names or the page is on, in table order, each once.
    static func matching(goal: String, url: String?) -> [Playbook] {
        let words = CommandGrammar.normalize(goal).map { w -> String in
            for suffix in ["'s", "\u{2019}s"] where w.hasSuffix(suffix) && w.count > suffix.count { return String(w.dropLast(suffix.count)) }
            return w
        }
        let host = url.flatMap { URL(string: $0)?.host?.lowercased() }
        return table.filter { p in
            if let host, p.hosts.contains(host) { return true }
            return p.phrases.contains { phrase in
                words.indices.contains { i in
                    i + phrase.count <= words.count && Array(words[i..<i + phrase.count]) == phrase
                        && !(i + phrase.count < words.count && p.notFollowedBy.contains(words[i + phrase.count]))
                }
            }
        }
    }

    /// The block for the user message; nil when no site matches.
    public static func block(goal: String, url: String?) -> String? {
        let found = matching(goal: goal, url: url)
        guard !found.isEmpty else { return nil }
        return "Site routes (written by NoHands, not by the page; follow one when it fits the goal):\n"
            + found.map { p in "\(p.name):\n" + p.lines.map { "  \($0)\n" }.joined() }.joined()
    }
}

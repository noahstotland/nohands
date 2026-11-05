import Foundation

/// Searching inside a site or an app: the result URL of sites with a known search page, and which on-screen
/// element is a search box.
public enum SiteSearch {
    /// Host (matched exactly or as a parent domain; the longest match wins) → the search URL the query is
    /// appended to, percent-encoded.
    static let templates: [String: String] = [
        "youtube.com": "https://www.youtube.com/results?search_query=",
        "google.com": "https://www.google.com/search?q=",
        "maps.google.com": "https://www.google.com/maps/search/",
        "bing.com": "https://www.bing.com/search?q=",
        "duckduckgo.com": "https://duckduckgo.com/?q=",
        "amazon.com": "https://www.amazon.com/s?k=",
        "ebay.com": "https://www.ebay.com/sch/i.html?_nkw=",
        "reddit.com": "https://www.reddit.com/search/?q=",
        "github.com": "https://github.com/search?q=",
        "wikipedia.org": "https://en.wikipedia.org/w/index.php?search=",
        "x.com": "https://x.com/search?q=",
        "twitter.com": "https://x.com/search?q=",
        "imdb.com": "https://www.imdb.com/find/?q=",
        "netflix.com": "https://www.netflix.com/search?q=",
        "twitch.tv": "https://www.twitch.tv/search?term=",
        "stackoverflow.com": "https://stackoverflow.com/search?q=",
        "pinterest.com": "https://www.pinterest.com/search/pins/?q=",
        "linkedin.com": "https://www.linkedin.com/search/results/all/?keywords=",
        "tiktok.com": "https://www.tiktok.com/search?q=",
        "instagram.com": "https://www.instagram.com/explore/search/keyword/?q=",
        "news.ycombinator.com": "https://hn.algolia.com/?q=",
        "spotify.com": "https://open.spotify.com/search/",
        "apple.com": "https://www.apple.com/us/search/",
    ]

    /// The search results page for `query` on the site at `host`; nil for a site with no known search page.
    public static func url(host: String, query: String) -> URL? {
        let h = host.lowercased()
        let match = templates.keys.filter { h == $0 || h.hasSuffix("." + $0) }.max { $0.count < $1.count }
        guard let match, let q = encoded(query) else { return nil }
        return URL(string: templates[match]! + q)
    }

    /// The search results page for `query` on a spoken site name ("youtube", "google maps") or a domain.
    public static func url(site spoken: String, query: String) -> URL? {
        guard let host = WebAddress.url(for: spoken)?.host else { return nil }
        return url(host: host, query: query)
    }

    /// Schemes a browser runs or opens instead of searching for, refused whatever follows the colon.
    static let refusedSchemes: Set<String> = [
        "javascript", "vbscript", "data", "file", "blob", "view-source", "about",
        "chrome", "edge", "brave", "opera", "vivaldi",
    ]

    /// What a search may type, on every route: control and format characters are dropped and runs of whitespace
    /// (tabs and newlines would become Tab and Return presses) collapse to one space. Text that starts with a
    /// scheme is refused when it is one a browser runs or opens ("javascript:", "file:", "chrome:"), or a
    /// non-http scheme glued to its payload ("foo:bar"); "note: buy milk" is plain words. Nil for blank or
    /// refused text.
    public static func typable(_ query: String) -> String? {
        let kept = query.unicodeScalars.filter { s in
            s.properties.isWhitespace || (s.properties.generalCategory != .control && s.properties.generalCategory != .format)
        }
        let q = String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !q.isEmpty else { return nil }
        if let m = q.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) {
            let scheme = q[m].dropLast().lowercased()
            let glued = q[m.upperBound...].first.map { !$0.isWhitespace } ?? false
            if refusedSchemes.contains(scheme) || (glued && scheme != "http" && scheme != "https") { return nil }
        }
        return q
    }

    static func encoded(_ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return q.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

/// Which accessibility element is an app's or a page's search box.
public enum SearchField {
    public static let roles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// A browser's address bar also calls itself a search bar ("Address and search bar", "Search or enter
    /// website name"); it is never the page's search box.
    static let excluded = ["address", "website", "url"]

    /// `names` are whatever labels the element carries (title, description, placeholder, identifier).
    public static func matches(role: String, subrole: String?, names: [String]) -> Bool {
        let lower = names.map { $0.lowercased() }
        if lower.contains(where: { n in excluded.contains { n.contains($0) } }) { return false }
        if subrole == "AXSearchField" { return true }
        guard roles.contains(role) else { return false }
        return lower.contains { $0.contains("search") }
    }

    /// The first search box in `elements` (the topmost, then leftmost), by role and title.
    public static func pick(from elements: [UIElementInfo]) -> UIElementInfo? {
        elements.filter { matches(role: $0.role, subrole: nil, names: [$0.title]) }
            .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }
}

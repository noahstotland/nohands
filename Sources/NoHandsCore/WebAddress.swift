import Foundation

/// Turns a spoken or model-written site reference into an `http(s)` URL: a known site name ("youtube"),
/// a bare domain ("youtube.com/@veritasium"), or a full URL. Anything else, including other schemes, is nil.
public enum WebAddress {
    /// Spoken names of sites that have no Mac app of the same name (so "open <name>" never hijacks an app).
    public static let knownSites: [String: String] = [
        "youtube": "https://www.youtube.com",
        "gmail": "https://mail.google.com",
        "google": "https://www.google.com",
        "google maps": "https://maps.google.com",
        "google docs": "https://docs.google.com",
        "google drive": "https://drive.google.com",
        "google calendar": "https://calendar.google.com",
        "reddit": "https://www.reddit.com",
        "github": "https://github.com",
        "twitter": "https://x.com",
        "x": "https://x.com",
        "facebook": "https://www.facebook.com",
        "instagram": "https://www.instagram.com",
        "tiktok": "https://www.tiktok.com",
        "pinterest": "https://www.pinterest.com",
        "linkedin": "https://www.linkedin.com",
        "netflix": "https://www.netflix.com",
        "hulu": "https://www.hulu.com",
        "disney plus": "https://www.disneyplus.com",
        "prime video": "https://www.primevideo.com",
        "twitch": "https://www.twitch.tv",
        "amazon": "https://www.amazon.com",
        "ebay": "https://www.ebay.com",
        "wikipedia": "https://www.wikipedia.org",
        "imdb": "https://www.imdb.com",
        "hacker news": "https://news.ycombinator.com",
        "stack overflow": "https://stackoverflow.com",
        "bbc": "https://www.bbc.com",
        "cnn": "https://www.cnn.com",
        "new york times": "https://www.nytimes.com",
        "espn": "https://www.espn.com",
        "weather": "https://weather.com",
        "yahoo": "https://www.yahoo.com",
        "bing": "https://www.bing.com",
        "duckduckgo": "https://duckduckgo.com",
        "apple": "https://www.apple.com",
    ]

    public static func url(for spoken: String) -> URL? {
        var t = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".,!?".contains(last) { t.removeLast() }
        guard !t.isEmpty else { return nil }
        let key = t.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if let known = knownSites[key] { return URL(string: known) }
        guard !t.contains(where: { $0.isWhitespace }) else { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let u = URL(string: t), let host = u.host, !host.isEmpty else { return nil }
            return u
        }
        guard !lower.contains(":") else { return nil }   // file:, javascript:, ftp: … never open
        let host = lower.split(whereSeparator: { "/?#".contains($0) }).first.map(String.init) ?? ""
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else { return nil }
        return URL(string: "https://" + t)
    }

    /// Endings common enough that typed text ending in one is taken as a web address. File extensions that are
    /// also real endings (`app`, `md`, `py`, `sh`, `zip`, `mov`, `rs`) are left out on purpose.
    static let commonEndings: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "co", "tv", "ai", "dev", "me", "info", "gg", "uk", "de", "fr", "ca",
        "au", "jp", "us",
    ]

    /// Stricter than `url(for:)`, for text the model typed: an explicit `http(s)://`, a `www.` start, or a host
    /// ending in a common web ending. Known site names without a dot ("apple"), file names ("notes.txt") and
    /// numbers ("3.14") are not addresses.
    public static func typedAddress(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".,!?".contains(last) { t.removeLast() }
        guard !t.contains(where: { $0.isWhitespace }), let url = url(for: t) else { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return url }
        let host = lower.split(whereSeparator: { "/?#".contains($0) }).first.map(String.init) ?? ""
        guard host.contains(".") else { return nil }
        let ending = host.split(separator: ".").last.map(String.init) ?? ""
        return host.hasPrefix("www.") || commonEndings.contains(ending) ? url : nil
    }
}

import Testing
import Foundation
import CoreGraphics
@testable import NoHandsCore

@Test func resultsPageForKnownHosts() {
    let cases: [(host: String, query: String, url: String?)] = [
        ("www.youtube.com", "outdoor boys", "https://www.youtube.com/results?search_query=outdoor%20boys"),
        ("m.youtube.com", "cats", "https://www.youtube.com/results?search_query=cats"),
        ("YOUTUBE.COM", "cats", "https://www.youtube.com/results?search_query=cats"),
        ("maps.google.com", "coffee", "https://www.google.com/maps/search/coffee"),          // longest match wins
        ("www.google.com", "a&b=c", "https://www.google.com/search?q=a%26b%3Dc"),             // never breaks the query
        ("notyoutube.com", "cats", nil),                                                      // suffix needs a dot
        ("example.org", "cats", nil),
        ("www.youtube.com", "   ", nil),
    ]
    for c in cases {
        #expect(SiteSearch.url(host: c.host, query: c.query)?.absoluteString == c.url, "\(c)")
    }
    #expect(SiteSearch.url(site: "youtube", query: "cats")?.absoluteString == "https://www.youtube.com/results?search_query=cats")
    #expect(SiteSearch.url(site: "google maps", query: "coffee")?.absoluteString == "https://www.google.com/maps/search/coffee")
    #expect(SiteSearch.url(site: "the kitchen", query: "cats") == nil)
    #expect(SiteSearch.url(site: "example.org", query: "cats") == nil)
}

@Test func searchFieldMatching() {
    let cases: [(role: String, subrole: String?, names: [String], hit: Bool)] = [
        ("AXTextField", nil, ["Search"], true),                             // YouTube's box (placeholder)
        ("AXComboBox", nil, ["Search Amazon"], true),
        ("AXTextField", "AXSearchField", [], true),                         // a native NSSearchField
        ("AXTextField", nil, ["Address and search bar"], false),            // Chrome's omnibox
        ("AXTextField", nil, ["Search or enter website name"], false),     // Safari's
        ("AXButton", nil, ["Search"], false),                               // the button beside the box
        ("AXTextField", nil, ["Email"], false),
        ("AXTextField", "AXSearchField", ["Address"], false),
    ]
    for c in cases {
        #expect(SearchField.matches(role: c.role, subrole: c.subrole, names: c.names) == c.hit, "\(c)")
    }
    let els = [
        UIElementInfo(id: 1, frame: CGRect(x: 0, y: 300, width: 100, height: 20), title: "Search", role: "AXTextField"),
        UIElementInfo(id: 2, frame: CGRect(x: 0, y: 10, width: 100, height: 20), title: "Search the docs", role: "AXTextField"),
        UIElementInfo(id: 3, frame: CGRect(x: 0, y: 0, width: 100, height: 20), title: "Search", role: "AXButton"),
    ]
    #expect(SearchField.pick(from: els)?.id == 2)   // the topmost box, never the button
}

@Test func typableSearchText() {
    let cases: [(text: String, out: String?)] = [
        ("outdoor  boys", "outdoor boys"),
        ("cats\nand\tdogs", "cats and dogs"),                 // tabs and newlines would be key presses
        ("   ", nil),
        ("javascript:alert(1)", nil),
        ("javascript: alert(1)", nil),                         // a space after the colon is still a script
        ("javascript:\talert(1)", nil),
        ("JavaScript:\u{00A0}alert(1)", nil),
        ("\u{01}javascript:alert(1)", nil),                    // control characters are dropped first
        ("\u{200B}javascript:alert(1)", nil),
        ("data: text/html,x", nil),
        ("file:///etc/hosts", nil),
        ("chrome://settings", nil),
        ("javascript:\u{1885}=1,alert(1)", nil),              // a combining mark after the colon must not hide it
        ("foo:\u{0301}bar", nil),
        ("foo:bar", nil),                                      // any non-http scheme glued to its payload
        ("https://example.org", "https://example.org"),
        ("note: buy milk", "note: buy milk"),                  // a colon followed by a space is plain words
        ("ratio 3:1", "ratio 3:1"),
    ]
    for c in cases {
        #expect(SiteSearch.typable(c.text) == c.out, "\(c)")
    }
}

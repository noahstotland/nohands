import Testing
import Foundation
@testable import NoHandsCore

@Test func knownSiteNamesResolveToURLs() {
    #expect(WebAddress.url(for: "youtube") == URL(string: "https://www.youtube.com"))
    #expect(WebAddress.url(for: "YouTube.") == URL(string: "https://www.youtube.com"))
    #expect(WebAddress.url(for: "gmail") == URL(string: "https://mail.google.com"))
    #expect(WebAddress.url(for: "hacker news") == URL(string: "https://news.ycombinator.com"))
}

@Test func domainsAndFullURLsResolve() {
    #expect(WebAddress.url(for: "youtube.com") == URL(string: "https://youtube.com"))
    #expect(WebAddress.url(for: "youtube.com/@veritasium/videos") == URL(string: "https://youtube.com/@veritasium/videos"))
    #expect(WebAddress.url(for: "http://example.org/a?b=1") == URL(string: "http://example.org/a?b=1"))
    #expect(WebAddress.url(for: "HTTPS://Example.org") == URL(string: "HTTPS://Example.org"))
}

@Test func nonWebInputsAreRejected() {
    #expect(WebAddress.url(for: "") == nil)
    #expect(WebAddress.url(for: "documents") == nil)           // not a site: stays an app name for the grammar
    #expect(WebAddress.url(for: "file:///etc/passwd") == nil)
    #expect(WebAddress.url(for: "javascript:alert(1)") == nil)
    #expect(WebAddress.url(for: "ftp://x.com") == nil)
    #expect(WebAddress.url(for: "not a url.com") == nil)
    #expect(WebAddress.url(for: "https://") == nil)
}

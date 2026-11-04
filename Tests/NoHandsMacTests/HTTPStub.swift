import Foundation

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var redirectTo: URL?
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data)?)?   // nil result = never respond
    nonisolated(unsafe) static var failWith: URLError?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let s = request.httpBodyStream {
            s.open(); defer { s.close() }
            var buf = [UInt8](repeating: 0, count: 65536)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(buf, count: n) }
        }
        Self.lock.lock(); Self.requests.append(request); Self.bodies.append(body); let h = Self.handler; Self.lock.unlock()
        guard let (status, data) = h?(request) else {
            if let e = Self.failWith { client?.urlProtocol(self, didFailWithError: e) }
            return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                   headerFields: Self.redirectTo.map { ["Location": $0.absoluteString] })!
        if let to = Self.redirectTo {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: resp)
        }
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func reset(_ h: ((URLRequest) -> (Int, Data)?)?) {
        lock.lock(); handler = h; requests = []; bodies = []; redirectTo = nil; failWith = nil; lock.unlock()
    }
}

func makeSession() -> URLSession {
    let c = URLSessionConfiguration.ephemeral
    c.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: c)
}


import Estimation
import Foundation
import Synchronization
import Tally
import Testing

@testable import PlateTally

/// Answers every request of the session that uses it, so no request leaves the test.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A body given to a session arrives at a protocol as a stream.
private func bytes(of request: URLRequest) -> Data {
    guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private let testKey = "test-key-value"
private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
private let request = HTTPRequest(
    url: endpoint, method: "POST", headers: ["content-type": "application/json", "anthropic-version": "v"],
    body: Data(#"{"hello":"model"}"#.utf8))

private final class Seen: Sendable {
    private let requests = Mutex<[URLRequest]>([])

    func add(_ request: URLRequest) { requests.withLock { $0.append(request) } }
    var all: [URLRequest] { requests.withLock { $0 } }
}

/// Answers a request to the API with a 307 to another host, and any other request with 200. After the
/// redirect it ends its own load, as the sample protocol of the platform vendor does: the loading system
/// starts a new load for the new request, or, when the redirect is refused, has the 3xx as the final response.
private final class RedirectingURLProtocol: URLProtocol {
    static let seen = Seen()
    static let elsewhere = URL(string: "https://elsewhere.invalid/v1/messages")!

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.add(request)
        guard request.url?.host() == endpoint.host() else {
            let ok = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var next = request
        next.url = Self.elsewhere
        let redirect = HTTPURLResponse(
            url: endpoint, statusCode: 307, httpVersion: nil, headerFields: ["Location": Self.elsewhere.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: redirect)
        client?.urlProtocol(self, didFailWithError: CocoaError(.userCancelled))
    }

    override func stopLoading() {}
}

/// The tests of this suite share one static handler, so they run one after another.
@Suite(.serialized) struct TransportTests {
    private func transport(key: String? = testKey) -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(keys: MemoryKeyStore(key), configuration: configuration)
    }

    private func answer(status: Int, body: String, seen: Seen = Seen()) {
        StubURLProtocol.handler = { received in
            seen.add(received)
            let response = HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    @Test func theRequestCarriesTheKeyInTheHeaderOnly() async throws {
        let seen = Seen()
        answer(status: 200, body: "{}", seen: seen)
        _ = try await transport().send(request)
        let received = try #require(seen.all.first)
        #expect(received.url == endpoint)
        #expect(received.httpMethod == "POST")
        #expect(received.value(forHTTPHeaderField: "x-api-key") == testKey)
        #expect(received.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(received.value(forHTTPHeaderField: "anthropic-version") == "v")
        #expect(bytes(of: received) == request.body)
        #expect(!received.url!.absoluteString.contains(testKey))
        #expect(!String(decoding: bytes(of: received), as: UTF8.self).contains(testKey))
    }

    @Test(arguments: [200, 429, 529])
    func theStatusAndTheBodyComeBack(status: Int) async throws {
        answer(status: status, body: "body \(status)")
        let response = try await transport().send(request)
        #expect(response == HTTPResponse(status: status, body: Data("body \(status)".utf8)))
    }

    @Test func aFailureOfTheNetworkIsReportedWithItsCode() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let failure = await #expect(throws: TransportFailure.self) { try await transport().send(request) }
        #expect(failure?.what == "the request did not complete")
        #expect(failure?.expected == "a response from api.anthropic.com")
        #expect(failure?.saw.hasPrefix("URL error -1009") == true)
    }

    /// A redirect would take the key, and with a 307 the photo, to another host in a second request
    /// (R4, R22, R23). Refused, the call ends with the redirect.
    @Test func aRedirectIsNotFollowed() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        let transport = URLSessionTransport(keys: MemoryKeyStore(testKey), configuration: configuration)
        let response = try? await transport.send(request)
        let seen = RedirectingURLProtocol.seen.all
        #expect(seen.count == 1)
        #expect(seen.allSatisfy { $0.url?.host() == endpoint.host() })
        #expect(response?.status != 200)
    }

    /// No cookie is stored or sent, and 60 s bound the whole call, not only the wait between two packets (D015).
    @Test func theSessionKeepsNoCookieAndGivesTheWholeCallSixtySeconds() {
        let configuration = transport().session.configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.timeoutIntervalForResource == 60)
    }

    @Test func withoutAKeyNothingIsSent() async {
        let seen = Seen()
        answer(status: 200, body: "{}", seen: seen)
        let failure = await #expect(throws: TransportFailure.self) { try await transport(key: nil).send(request) }
        #expect(failure?.what == "no API key is set")
        #expect(seen.all.isEmpty)
    }
}

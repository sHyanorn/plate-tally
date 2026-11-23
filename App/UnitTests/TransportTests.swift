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

    @Test func withoutAKeyNothingIsSent() async {
        let seen = Seen()
        answer(status: 200, body: "{}", seen: seen)
        let failure = await #expect(throws: TransportFailure.self) { try await transport(key: nil).send(request) }
        #expect(failure?.what == "no API key is set")
        #expect(seen.all.isEmpty)
    }
}

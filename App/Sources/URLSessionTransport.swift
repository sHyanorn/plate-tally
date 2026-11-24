import Core
import Estimation
import Foundation
import Tally

/// The one place that talks to the network (R22). It adds the key just before the request leaves, so the
/// key is in no record, no log and no package code (R23). It never retries (R7).
struct URLSessionTransport: Sendable {
    private static let timeout: TimeInterval = 60

    let keys: any KeyStore
    let session: URLSession

    /// The default session keeps no cache and no cookies. It follows no redirect.
    init(keys: any KeyStore, configuration: URLSessionConfiguration = .ephemeral) {
        self.keys = keys
        self.session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    }

    var transport: Transport {
        { [self] request throws(TransportFailure) in try await send(request) }
    }

    func send(_ request: HTTPRequest) async throws(TransportFailure) -> HTTPResponse {
        let key: String?
        do throws(KeychainError) {
            key = try keys.read()
        } catch {
            throw TransportFailure(what: error.what, expected: error.expected, saw: error.saw)
        }
        guard let key else {
            let missing = MissingKey()
            throw TransportFailure(what: missing.what, expected: missing.expected, saw: missing.saw)
        }
        var urlRequest = URLRequest(url: request.url, timeoutInterval: Self.timeout)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.setValue(key, forHTTPHeaderField: Estimation.keyHeader)
        urlRequest.httpBody = request.body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw Self.failure(error, host: request.url.host() ?? request.url.absoluteString)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TransportFailure(
                what: "the response is not an HTTP response", expected: "an HTTP response",
                saw: String(describing: type(of: response)))
        }
        return HTTPResponse(status: http.statusCode, body: data)
    }

    private static func failure(_ error: any Error, host: String) -> TransportFailure {
        let reason =
            (error as? URLError).map { "URL error \($0.code.rawValue), \($0.localizedDescription)" }
            ?? String(describing: error)
        return TransportFailure(what: "the request did not complete", expected: "a response from \(host)", saw: reason)
    }
}

/// Refuses every redirect, so a 3xx is the final response and reaches the package, which takes it for an error.
/// Followed, it would carry the key, and with a 307 the photo, to another host in a second request (R4, R22, R23).
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

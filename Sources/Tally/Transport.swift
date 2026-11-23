import Core
import Estimation
import Foundation

public struct HTTPResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// The request did not come back with a response: no network, a timeout, a cancel.
public struct TransportFailure: PlateError, Equatable {
    public let what: String
    public let expected: String
    public let saw: String

    public init(what: String, expected: String, saw: String) {
        self.what = what
        self.expected = expected
        self.saw = saw
    }
}

/// Sends one request. The app supplies it: it adds the key and talks to the network, so the key never
/// passes through the package (R23) and a test needs no network.
public typealias Transport = @Sendable (HTTPRequest) async throws(TransportFailure) -> HTTPResponse

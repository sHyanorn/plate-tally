import Core
import Estimation
import Foundation
import Synchronization

@testable import Tally

// No photo is used: the segments of a 4 x 3 JPEG are built by hand.

private func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
    let length = payload.count + 2
    return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
}

func testImage() throws -> JPEGImage {
    let quantization = segment(0xDB, [0] + [UInt8](repeating: 1, count: 64))
    let frame = segment(0xC0, [8, 0, 3, 0, 4, 1, 1, 0x11, 0])
    let scan = segment(0xDA, [1, 1, 0, 0, 63, 0]) + [0x12, 0x34]
    return try JPEGImage(encoded: Data([0xFF, 0xD8] + quantization + frame + scan + [0xFF, 0xD9]))
}

/// 1,200 input and 110 output tokens cost 0.0024 + 0.0011 = 0.0035 USD.
func responseBody(text: String, input: Int = 1200, output: Int = 110) throws -> Data {
    let message: [String: Any] = [
        "content": [["type": "text", "text": text]],
        "stop_reason": "end_turn",
        "usage": ["input_tokens": input, "output_tokens": output],
    ]
    return try JSONSerialization.data(withJSONObject: message)
}

let twoItems = #"{"items":[{"name":"rice","grams":150,"kcal":195},{"name":"chicken","grams":100,"kcal":165}]}"#
let usd0035 = Decimal(string: "0.0035")!

/// A transport that records what it was given and answers with one fixed result, after a delay if given.
final class RecordingTransport: Sendable {
    private let requests = Mutex<[HTTPRequest]>([])
    private let answer: Result<HTTPResponse, TransportFailure>
    private let delay: Duration

    init(_ answer: Result<HTTPResponse, TransportFailure>, delay: Duration = .zero) {
        self.answer = answer
        self.delay = delay
    }

    convenience init(status: Int = 200, body: Data, delay: Duration = .zero) {
        self.init(.success(HTTPResponse(status: status, body: body)), delay: delay)
    }

    var sent: [HTTPRequest] { requests.withLock { $0 } }

    var transport: Transport {
        { [self] request throws(TransportFailure) in
            requests.withLock { $0.append(request) }
            if delay > .zero { try? await Task.sleep(for: delay) }
            return try answer.get()
        }
    }
}

func meal(_ text: String = "2026-11-23T12:30", id: Int = 1, items: [FoodItem]? = nil) throws -> Meal {
    Meal(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
        at: try LocalDateTime(text),
        items: items ?? [FoodItem(name: "rice", grams: 150, kcal: 195)])
}

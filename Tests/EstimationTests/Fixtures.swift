import Core
import Foundation
import Testing

@testable import Estimation

// MARK: JPEG bytes. No photo is used: the segments are built by hand.

func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
    let length = payload.count + 2
    return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
}

let jfif = segment(0xE0, Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
let quantization = segment(0xDB, [0] + [UInt8](repeating: 1, count: 64))
/// Entropy-coded data with a stuffed zero (FF 00) and a restart marker (FF D0), which are not markers.
let scan = segment(0xDA, [1, 1, 0, 0, 63, 0]) + [0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56]
let endOfImage: [UInt8] = [0xFF, 0xD9]

func frame(width: Int, height: Int, marker: UInt8 = 0xC0) -> [UInt8] {
    segment(
        marker,
        [8, UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8), UInt8(width & 0xFF), 1, 1, 0x11, 0])
}

func jpeg(_ parts: [UInt8]...) -> Data {
    Data([0xFF, 0xD8] + parts.flatMap { $0 })
}

func cleanJPEG(width: Int = 4, height: Int = 3) -> Data {
    jpeg(jfif, quantization, frame(width: width, height: height), scan, endOfImage)
}

// MARK: Responses of the API

/// The body of a 200 response with one text block, or with the given blocks.
func response(
    text: String? = nil, blocks: [[String: Any]]? = nil, stop: String? = "end_turn",
    input: Int = 100, output: Int = 50, extraUsage: [String: Any] = [:]
) throws -> Data {
    var usage: [String: Any] = ["input_tokens": input, "output_tokens": output]
    usage.merge(extraUsage) { _, new in new }
    var message: [String: Any] = [
        "id": "msg_01", "type": "message", "role": "assistant", "model": Estimation.model,
        "content": blocks ?? [["type": "text", "text": text ?? ""]],
        "usage": usage,
    ]
    message["stop_reason"] = stop ?? NSNull()
    return try JSONSerialization.data(withJSONObject: message)
}

func read(_ text: String) throws -> Reply {
    try Estimation.read(status: 200, body: response(text: text))
}

/// The reason code of a reply that is rejected, or nil when it is accepted.
func rejection(_ text: String) throws -> EstimationError.Reason? {
    if case .failure(let error) = try read(text).items { return error.reason }
    return nil
}

func accepted(_ text: String) throws -> [FoodItem] {
    try read(text).items.get()
}

func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
}

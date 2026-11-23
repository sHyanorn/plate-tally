import Core
import Foundation

public enum JPEGError: PlateError, Equatable {
    case notJPEG(start: [UInt8])
    case truncated(at: Int)
    case malformed(String, at: Int)
    case tooLarge(width: Int, height: Int)

    public var what: String {
        switch self {
        case .notJPEG: "the image is not a JPEG"
        case .truncated: "the JPEG is cut off"
        case .malformed: "the JPEG is malformed"
        case .tooLarge: "the image is too large"
        }
    }

    public var expected: String {
        switch self {
        case .notJPEG: "bytes that start with FF D8"
        case .truncated: "complete segments up to the end marker FF D9"
        case .malformed: "markers and segments as the format defines them"
        case .tooLarge: "a long side of at most \(JPEGImage.maxLongSide) px"
        }
    }

    public var saw: String {
        switch self {
        case .notJPEG(let start):
            start.isEmpty ? "no bytes" : start.map { String($0, radix: 16, uppercase: true) }.joined(separator: " ")
        case .truncated(let offset): "a segment that ends after the last byte, at offset \(offset)"
        case .malformed(let detail, let offset): "\(detail) at offset \(offset)"
        case .tooLarge(let width, let height): "\(width) x \(height) px"
        }
    }
}

/// A JPEG that may be sent: no metadata (R3) and a long side of at most 1024 px (R2).
/// The bytes are those of the input without the segments that can carry a location, a time or a
/// device: every APPn segment except the JFIF header and the ICC profile, and every comment.
/// Everything after the first end marker is dropped too, which removes images appended to the file.
public struct JPEGImage: Equatable, Sendable {
    public static let maxLongSide = 1024

    public let bytes: Data
    public let width: Int
    public let height: Int

    public init(encoded: Data) throws(JPEGError) {
        let input = [UInt8](encoded)
        guard input.count >= 2, input[0] == 0xFF, input[1] == 0xD8 else {
            throw .notJPEG(start: Array(input.prefix(2)))
        }
        var output: [UInt8] = [0xFF, 0xD8]
        var position = 2
        var size: (width: Int, height: Int)?
        var scans = 0
        while true {
            guard position < input.count else { throw .truncated(at: position) }
            guard input[position] == 0xFF else {
                throw .malformed("expected a marker prefix FF", at: position)
            }
            // Any number of FF bytes may pad a marker.
            while position + 1 < input.count, input[position + 1] == 0xFF { position += 1 }
            guard position + 1 < input.count else { throw .truncated(at: position) }
            let marker = input[position + 1]
            if marker == 0xD9 {
                output += [0xFF, 0xD9]
                break
            }
            guard Self.hasSegment(marker) else {
                throw .malformed("the marker FF \(String(marker, radix: 16, uppercase: true)) outside the image data", at: position)
            }
            guard position + 4 <= input.count else { throw .truncated(at: position) }
            let length = Int(input[position + 2]) << 8 | Int(input[position + 3])
            let end = position + 2 + length
            guard length >= 2, end <= input.count else { throw .truncated(at: position) }
            let payload = input[(position + 4)..<end]
            if Self.keeps(marker, payload) { output += input[position..<end] }
            if Self.isFrameHeader(marker) { size = try Self.frameSize(Array(payload), at: position) }
            position = end
            if marker == 0xDA {
                scans += 1
                let next = Self.endOfScan(input, from: position)
                output += input[position..<next]
                position = next
            }
        }
        guard let size else { throw .malformed("no frame header", at: position) }
        guard scans > 0 else { throw .malformed("no image data", at: position) }
        guard max(size.width, size.height) <= Self.maxLongSide else {
            throw .tooLarge(width: size.width, height: size.height)
        }
        self.bytes = Data(output)
        self.width = size.width
        self.height = size.height
    }

    /// Markers without a length: the fill and restart markers and TEM.
    private static func hasSegment(_ marker: UInt8) -> Bool {
        !(marker == 0x00 || marker == 0x01 || (0xD0...0xD8).contains(marker))
    }

    private static func keeps(_ marker: UInt8, _ payload: ArraySlice<UInt8>) -> Bool {
        switch marker {
        case 0xE0: payload.starts(with: Array("JFIF\0".utf8))
        case 0xE2: payload.starts(with: Array("ICC_PROFILE\0".utf8))
        case 0xE1, 0xE3...0xEF, 0xFE: false
        default: true
        }
    }

    /// The frame headers SOF0 to SOF15, except DHT, JPG and DAC, which share the range.
    private static func isFrameHeader(_ marker: UInt8) -> Bool {
        (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
    }

    private static func frameSize(_ payload: [UInt8], at offset: Int) throws(JPEGError) -> (width: Int, height: Int) {
        guard payload.count >= 6 else { throw .malformed("a frame header shorter than 6 bytes", at: offset) }
        let height = Int(payload[1]) << 8 | Int(payload[2])
        let width = Int(payload[3]) << 8 | Int(payload[4])
        guard width > 0, height > 0 else {
            throw .malformed("a frame of \(width) x \(height) px", at: offset)
        }
        return (width, height)
    }

    /// The index of the marker that ends the entropy-coded data of a scan: the next FF that is not
    /// a stuffed zero, a restart marker or padding. The end of the input if there is none.
    private static func endOfScan(_ input: [UInt8], from start: Int) -> Int {
        var index = start
        while index + 1 < input.count {
            guard input[index] == 0xFF else {
                index += 1
                continue
            }
            let next = input[index + 1]
            if next == 0x00 || (0xD0...0xD7).contains(next) {
                index += 2
            } else if next == 0xFF {
                index += 1
            } else {
                return index
            }
        }
        return input.count
    }
}

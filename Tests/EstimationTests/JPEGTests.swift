import Foundation
import Testing

@testable import Estimation

private let exifGPS = segment(0xE1, Array("Exif\0\0".utf8) + Array("GPSLatitudeRef N".utf8))
private let xmp = segment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta/>".utf8))

@Suite struct JPEGTests {
    @Test func cleanFileIsKeptByteForByte() throws {
        let data = cleanJPEG()
        let image = try JPEGImage(encoded: data)
        #expect(image.bytes == data)
        #expect(image.width == 4 && image.height == 3)
    }

    @Test(arguments: [
        ("Exif", exifGPS),
        ("XMP", xmp),
        ("IPTC", segment(0xED, Array("Photoshop 3.0\0".utf8))),
        ("comment", segment(0xFE, Array("shot on a phone".utf8))),
        ("Adobe", segment(0xEE, Array("Adobe\0".utf8) + [0, 100, 0, 0, 0, 1])),
        ("multi-picture", segment(0xE2, Array("MPF\0".utf8) + [1, 2, 3, 4])),
        ("JFXX thumbnail", segment(0xE0, Array("JFXX\0".utf8) + [0x10, 1, 2, 3])),
        ("APP3", segment(0xE3, [1, 2, 3])),
        ("APP15", segment(0xEF, [1, 2, 3])),
    ])
    func dropsMetadataSegment(name: String, metadata: [UInt8]) throws {
        let dirty = jpeg(jfif, metadata, quantization, frame(width: 4, height: 3), scan, endOfImage)
        #expect(try JPEGImage(encoded: dirty).bytes == cleanJPEG(), "\(name) was kept")
    }

    @Test func keepsTheIccProfile() throws {
        let icc = segment(0xE2, Array("ICC_PROFILE\0".utf8) + [1, 1, 9, 9])
        let data = jpeg(jfif, icc, quantization, frame(width: 4, height: 3), scan, endOfImage)
        #expect(try JPEGImage(encoded: data).bytes == data)
    }

    @Test func dropsMetadataBetweenTheScansOfAProgressiveFile() throws {
        let huffman = segment(0xC4, [0x00] + [UInt8](repeating: 0, count: 16))
        func file(_ between: [UInt8]) -> Data {
            jpeg(
                jfif, quantization, frame(width: 4, height: 3, marker: 0xC2), scan, between, huffman, scan,
                endOfImage)
        }
        #expect(try JPEGImage(encoded: file(exifGPS)).bytes == file([]))
    }

    @Test func dropsWhatFollowsTheFirstEndMarker() throws {
        let second = cleanJPEG() + Data(exifGPS)
        let image = try JPEGImage(encoded: cleanJPEG() + second)
        #expect(image.bytes == cleanJPEG())
    }

    @Test func paddingBeforeAMarkerIsAccepted() throws {
        let padded = jpeg(jfif, [0xFF, 0xFF], quantization, frame(width: 4, height: 3), scan, endOfImage)
        #expect(try JPEGImage(encoded: padded).bytes == cleanJPEG())
    }

    @Test(arguments: [(1024, 768), (768, 1024), (1024, 1024), (1, 1), (640, 480)])
    func acceptsALongSideUpTo1024(width: Int, height: Int) throws {
        let image = try JPEGImage(encoded: cleanJPEG(width: width, height: height))
        #expect(image.width == width && image.height == height)
    }

    @Test(arguments: [(1025, 100), (100, 1025), (4032, 3024), (3024, 4032)])
    func rejectsALongSideAbove1024(width: Int, height: Int) {
        #expect(throws: JPEGError.tooLarge(width: width, height: height)) {
            try JPEGImage(encoded: cleanJPEG(width: width, height: height))
        }
    }

    @Test func tooLargeErrorStatesWhatExpectedAndSaw() {
        let error = #expect(throws: JPEGError.self) {
            try JPEGImage(encoded: cleanJPEG(width: 4032, height: 3024))
        }
        #expect(
            error?.description
                == "the image is too large: expected a long side of at most 1024 px, saw 4032 x 3024 px")
    }

    @Test(arguments: [
        ("nothing", Data(), JPEGError.notJPEG(start: [])),
        ("a PNG", Data([0x89, 0x50, 0x4E, 0x47]), .notJPEG(start: [0x89, 0x50])),
        ("one byte", Data([0xFF]), .notJPEG(start: [0xFF])),
        ("start marker only", Data([0xFF, 0xD8]), .truncated(at: 2)),
        ("no marker prefix", jpeg([0x00, 0x01]), .malformed("expected a marker prefix FF", at: 2)),
        ("a restart marker in the header", jpeg([0xFF, 0xD0]), .malformed("the marker FF D0 outside the image data", at: 2)),
        ("a cut segment", Data(jpeg(jfif).dropLast(3)), .truncated(at: 2)),
        ("a segment shorter than its length field", jpeg([0xFF, 0xE0, 0x00, 0x01]), .truncated(at: 2)),
        ("no end marker", Data(cleanJPEG().dropLast(2)), .truncated(at: cleanJPEG().count - 2)),
    ])
    func rejectsBrokenFiles(name: String, data: Data, error: JPEGError) {
        #expect(throws: error, "\(name)") { try JPEGImage(encoded: data) }
    }

    @Test func rejectsAFileWithoutFrameHeaderOrScan() {
        let noFrame = jpeg(jfif, quantization, scan, endOfImage)
        #expect(throws: JPEGError.self) { try JPEGImage(encoded: noFrame) }
        let noScan = jpeg(jfif, quantization, frame(width: 4, height: 3), endOfImage)
        #expect(throws: JPEGError.self) { try JPEGImage(encoded: noScan) }
    }

    @Test func rejectsAFrameWithoutSize() {
        #expect(throws: JPEGError.self) {
            try JPEGImage(encoded: jpeg(jfif, quantization, frame(width: 0, height: 3), scan, endOfImage))
        }
    }
}

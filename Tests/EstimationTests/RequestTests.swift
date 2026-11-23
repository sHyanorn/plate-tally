import Foundation
import Testing

@testable import Estimation

@Suite struct PromptTests {
    /// D009 measured the prompt in eval/prompts/p2.txt, so the app must send those bytes. The
    /// evaluation strips the file's surrounding whitespace. Strings are not compared: Swift calls
    /// two canonically equivalent spellings equal, and the API sees bytes.
    @Test func equalsTheMeasuredFileByteForByte() throws {
        let file = repoRoot().appendingPathComponent("eval/prompts/p2.txt")
        var bytes = ArraySlice(try Data(contentsOf: file))
        let space: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        while let first = bytes.first, space.contains(first) { bytes.removeFirst() }
        while let last = bytes.last, space.contains(last) { bytes.removeLast() }
        #expect(Array(Prompt.p2.utf8) == Array(bytes))
    }
}

@Suite struct RequestTests {
    private func sent() throws -> (request: HTTPRequest, json: [String: Any], image: JPEGImage) {
        let image = try JPEGImage(encoded: cleanJPEG())
        let request = Estimation.request(image: image)
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        return (request, json, image)
    }

    @Test func destinationAndHeaders() throws {
        let (request, _, _) = try sent()
        #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.method == "POST")
        #expect(request.headers == ["content-type": "application/json", "anthropic-version": "2026-10-21"])
    }

    @Test func theKeyIsNotInTheRequest() throws {
        let (request, _, _) = try sent()
        #expect(request.headers[Estimation.keyHeader] == nil)
        #expect(Estimation.keyHeader == "x-api-key")
    }

    /// Exactly the parameters of the evaluation: no system prompt, no tool, no sampling, no fallback.
    @Test func bodyHasTheMeasuredParametersOnly() throws {
        let (_, json, _) = try sent()
        #expect(Set(json.keys) == ["model", "max_tokens", "thinking", "messages"])
        #expect(json["model"] as? String == "claude-sonnet-5-5")
        #expect(json["max_tokens"] as? Int == 600)
        #expect(json["thinking"] as? [String: String] == ["type": "between_tools"])
    }

    @Test func oneUserMessageWithTheImageThenThePrompt() throws {
        let (_, json, image) = try sent()
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "image")
        let source = try #require(content[0]["source"] as? [String: String])
        #expect(source["type"] == "base64")
        #expect(source["media_type"] == "image/jpeg")
        #expect(Data(base64Encoded: try #require(source["data"])) == image.bytes)
        #expect(content[1] as? [String: String] == ["type": "text", "text": Prompt.p2])
    }

    @Test func bodyIsTheSameBytesEveryTimeAndKeepsSlashes() throws {
        let image = try JPEGImage(encoded: cleanJPEG())
        let body = Estimation.request(image: image).body
        #expect(body == Estimation.request(image: image).body)
        let text = String(decoding: body, as: UTF8.self)
        // A JPEG starts with FF D8 FF, which is /9j/ in base64.
        #expect(text.contains("/9j/"))
        #expect(!text.contains("\\/"))
    }

    @Test func theImageSentHasNoMetadata() throws {
        let exif = segment(0xE1, Array("Exif\0\0GPS".utf8))
        let image = try JPEGImage(
            encoded: jpeg(jfif, exif, quantization, frame(width: 4, height: 3), scan, endOfImage))
        let body = Estimation.request(image: image).body
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let content = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        let data = try #require((content[0]["source"] as? [String: String])?["data"])
        let sent = try #require(Data(base64Encoded: data))
        #expect(sent == cleanJPEG())
        #expect(sent.range(of: Data("Exif".utf8)) == nil)
    }
}

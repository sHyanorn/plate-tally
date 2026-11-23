import Foundation
import Testing

@testable import Estimation

@Suite struct RecordedRepliesTests {
    /// The 300 replies recorded for the chosen model and prompt in the evaluation (D009), judged by
    /// the rules of the app. The evaluation found 295 valid, 4 with prose before the object and 1
    /// with the wrong keys, and 169,800 input and 36,295 output tokens in all.
    @Test func recordedRepliesAreJudgedAsTheEvaluationJudgedThem() throws {
        let folder = repoRoot().appendingPathComponent("eval/raw/claude-sonnet-5-5/p2")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count == 300)

        var failures: [EstimationError.Reason: Int] = [:]
        var valid = 0
        var kcal = 0.0
        var inputTokens = 0
        var outputTokens = 0
        for file in files {
            let record = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            let message = try #require(record["response"] as? [String: Any])
            let reply = try Estimation.read(status: 200, body: JSONSerialization.data(withJSONObject: message))
            inputTokens += reply.usage.inputTokens
            outputTokens += reply.usage.outputTokens
            switch reply.items {
            case .success(let items):
                valid += 1
                kcal += items.reduce(0) { $0 + $1.kcal }
            case .failure(let error):
                failures[error.reason, default: 0] += 1
            }
        }
        #expect(valid == 295)
        #expect(failures == [.notJSON: 4, .wrongKeys: 1])
        #expect(abs(kcal - 78885) < 1e-6)
        #expect(inputTokens == 169_800 && outputTokens == 36_295)
    }
}

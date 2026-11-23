import Foundation
import Testing

@testable import Estimation

/// One row of eval/results/per_call.tsv, the evaluation's verdict on one recorded call.
private struct EvaluationRow {
    let status: String
    let reason: String
    let predictedKcal: Double?
    let inputTokens: Int
    let outputTokens: Int
}

/// The rows of one model and prompt, by dish id.
private func evaluationRows(model: String, prompt: String) throws -> [String: EvaluationRow] {
    let file = repoRoot().appendingPathComponent("eval/results/per_call.tsv")
    let lines = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
    let header = try #require(lines.first)
    func column(_ name: String) throws -> Int { try #require(header.firstIndex { $0 == name }, "no column \(name)") }
    let (modelAt, promptAt, dishAt) = (try column("model"), try column("prompt"), try column("dish_id"))
    let (statusAt, reasonAt, kcalAt) = (try column("status"), try column("reason"), try column("pred_kcal"))
    let (inputAt, outputAt) = (try column("input_tokens"), try column("output_tokens"))

    var rows: [String: EvaluationRow] = [:]
    for fields in lines.dropFirst() where fields[modelAt] == model && fields[promptAt] == prompt {
        rows[String(fields[dishAt])] = EvaluationRow(
            status: String(fields[statusAt]), reason: String(fields[reasonAt]),
            predictedKcal: Double(fields[kcalAt]),
            inputTokens: try #require(Int(fields[inputAt])), outputTokens: try #require(Int(fields[outputAt])))
    }
    return rows
}

/// The body of each recorded response of one model and prompt, by dish id.
private func recordedResponses(model: String, prompt: String) throws -> [String: Data] {
    let folder = repoRoot().appendingPathComponent("eval/raw/\(model)/\(prompt)")
    var bodies: [String: Data] = [:]
    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    where file.pathExtension == "json" {
        let record = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let message = try #require(record["response"] as? [String: Any])
        bodies[file.deletingPathExtension().lastPathComponent] = try JSONSerialization.data(withJSONObject: message)
    }
    return bodies
}

@Suite struct RecordedRepliesTests {
    /// The 300 replies recorded for the chosen model and prompt in the evaluation (D009), each judged
    /// by the rules of the app and compared with the evaluation's row for the same dish: 295 valid, 4
    /// with prose before the object, 1 with the wrong keys.
    @Test func eachRecordedReplyIsJudgedAsTheEvaluationJudgedIt() throws {
        let rows = try evaluationRows(model: "claude-sonnet-5-5", prompt: "p2")
        let bodies = try recordedResponses(model: "claude-sonnet-5-5", prompt: "p2")
        #expect(bodies.count == 300 && Set(bodies.keys) == Set(rows.keys))

        for (dish, body) in bodies {
            let row = try #require(rows[dish], "no row for \(dish)")
            let reply = try Estimation.read(status: 200, body: body)
            switch reply.items {
            case .success(let items):
                #expect(row.status == "ok" && row.reason == "", "\(dish): status \(row.status)")
                #expect(row.predictedKcal == items.reduce(0) { $0 + $1.kcal }, "\(dish): kcal")
            case .failure(let error):
                #expect(row.status == "invalid" && row.reason == error.reason.rawValue, "\(dish): \(error.reason)")
                #expect(row.predictedKcal == nil, "\(dish): kcal")
            }
            #expect(row.inputTokens == reply.usage.inputTokens, "\(dish): input tokens")
            #expect(row.outputTokens == reply.usage.outputTokens, "\(dish): output tokens")
        }
    }
}

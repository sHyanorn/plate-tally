import Core
import Estimation
import Foundation
import Testing

@testable import Cost

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
}

func decimal(_ text: String) -> Decimal { Decimal(string: text)! }

private let sonnet = "claude-sonnet-5-5"

@Suite struct PricingTests {
    @Test func theTableHoldsTheSpecPricesAndTheDayTheyWereRead() {
        #expect(Pricing.table.count == 1)
        #expect(Pricing.table[sonnet] == Price(input: 2, output: 10))
        #expect(Pricing.readOn == "2026-11-22")
    }

    @Test func theModelTheAppSendsHasAPrice() {
        #expect(Pricing.table[Estimation.model] != nil)
    }

    @Test(arguments: [
        (566, 107, "0.002202"), (1_000_000, 0, "2"), (0, 1_000_000, "10"), (0, 0, "0"), (1, 0, "0.000002"),
        (0, 1, "0.00001"), (1036, 3, "0.002102"), (169_800, 36_295, "0.70255"),
    ])
    func costIsInputAndOutputTokensTimesTheirPrices(input: Int, output: Int, usd: String) throws {
        #expect(try Pricing.cost(of: Usage(inputTokens: input, outputTokens: output), model: sonnet) == decimal(usd))
    }

    /// A Double sum of ten 0.000002 is not 0.00002. A Decimal sum is.
    @Test func sumsAreExact() throws {
        let one = try Pricing.cost(of: Usage(inputTokens: 1, outputTokens: 0), model: sonnet)
        #expect((0..<10).reduce(Decimal.zero) { total, _ in total + one } == decimal("0.00002"))
    }

    @Test func anUnknownModelIsRefusedWithTheKnownOnes() {
        let error = #expect(throws: CostError.self) {
            try Pricing.cost(of: Usage(inputTokens: 1, outputTokens: 1), model: "no-such-model")
        }
        #expect(error == .unknownModel("no-such-model", known: [sonnet]))
        #expect(error?.description == "the model has no price: expected one of claude-sonnet-5-5, saw no-such-model")
    }

    /// A reply that fails R5 or R6 comes back with its usage, and the call is billed all the same.
    @Test func aReplyThatFailsValidationIsStillCosted() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "about 300 kcal"]], "stop_reason": "end_turn",
            "usage": ["input_tokens": 1036, "output_tokens": 3],
        ])
        let reply = try Estimation.read(status: 200, body: body)
        #expect(reply.items.isFailure)
        #expect(try Pricing.cost(of: reply.usage, model: sonnet) == decimal("0.002102"))
    }
}

@Suite struct RecordedCallsTests {
    private func rows() throws -> [String: Double] {
        let file = repoRoot().appendingPathComponent("eval/results/per_call.tsv")
        let lines = String(decoding: try Data(contentsOf: file), as: UTF8.self).split(separator: "\n")
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
        let header = try #require(lines.first)
        let (model, prompt) = (try #require(header.firstIndex { $0 == "model" }), try #require(header.firstIndex { $0 == "prompt" }))
        let (dish, cost) = (try #require(header.firstIndex { $0 == "dish_id" }), try #require(header.firstIndex { $0 == "cost_usd" }))
        var costs: [String: Double] = [:]
        for fields in lines.dropFirst() where fields[model] == sonnet && fields[prompt] == "p2" {
            let usd = try #require(Double(String(fields[cost])))
            costs[String(fields[dish])] = usd
        }
        return costs
    }

    /// The 300 recorded calls of the chosen model and prompt (D009): 169,800 input and 36,295 output
    /// tokens, 0.70255 USD. The cost_usd column of eval/results/per_call.tsv sums to the same number.
    @Test func theRecordedCallsCostWhatTheEvaluationSaidIncludingTheInvalidOnes() throws {
        let expected = try rows()
        let folder = repoRoot().appendingPathComponent("eval/raw/\(sonnet)/p2")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 300 && expected.count == 300)

        var total = Decimal.zero
        var tokens = (input: 0, output: 0)
        var invalid = 0
        for file in files {
            let record = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            let message = try #require(record["response"] as? [String: Any])
            let reply = try Estimation.read(status: 200, body: JSONSerialization.data(withJSONObject: message))
            let cost = try Pricing.cost(of: reply.usage, model: sonnet)
            let dish = file.deletingPathExtension().lastPathComponent
            // The evaluation computed in binary floats, so its column is off by up to 1e-18 per row.
            #expect(abs(NSDecimalNumber(decimal: cost).doubleValue - (expected[dish] ?? .nan)) < 1e-12, "\(dish)")
            total += cost
            tokens.input += reply.usage.inputTokens
            tokens.output += reply.usage.outputTokens
            if reply.items.isFailure { invalid += 1 }
        }
        #expect(invalid == 5)
        #expect(tokens.input == 169_800 && tokens.output == 36_295)
        #expect(total == decimal("0.70255"))
    }
}

extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

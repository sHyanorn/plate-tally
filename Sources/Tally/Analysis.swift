import Core
import Cost
import Estimation
import Foundation

public struct MissingKey: PlateError, Equatable {
    public init() {}

    public var what: String { "no API key is set" }
    public var expected: String { "a key saved in settings" }
    public var saw: String { "no key" }
}

/// One analysis of one photo, from the checks before the call to the record after it.
public enum Analysis {
    public struct Outcome: Equatable, Sendable {
        /// Present when the API billed the call, whether or not the reply is usable (R17).
        public let call: CallRecord?
        public let items: Result<[FoodItem], Problem>
    }

    /// Why an analysis may not start, or nil: no key (R20), or the daily limit reached by the calls logged
    /// and those in flight (R19).
    public static func refusal(hasKey: Bool, log: CallLog, inFlight: Int, on day: LocalDay, limit: Int) -> Problem? {
        guard hasKey else { return Problem(MissingKey()) }
        do throws(CostError) {
            try log.requireRoom(on: day, limit: limit, inFlight: inFlight)
        } catch {
            return Problem(error)
        }
        return nil
    }

    /// Makes one call and never repeats it (R7). The caller asks `refusal` first and adds `call` to its log.
    public static func run(image: JPEGImage, at: LocalDateTime, send: Transport) async -> Outcome {
        let response: HTTPResponse
        do throws(TransportFailure) {
            response = try await send(Estimation.request(image: image))
        } catch {
            return Outcome(call: nil, items: .failure(Problem(error)))
        }
        // A response without usage, an HTTP error for one, is not billed and so not recorded.
        let reply: Reply
        do throws(EstimationError) {
            reply = try Estimation.read(status: response.status, body: response.body)
        } catch {
            return Outcome(call: nil, items: .failure(Problem(error, code: error.reason.rawValue)))
        }
        let call: CallRecord
        do throws(CostError) {
            call = try CallRecord(at: at, model: Estimation.model, usage: reply.usage)
        } catch {
            return Outcome(call: nil, items: .failure(Problem(error)))
        }
        switch reply.items {
        case .success(let items):
            return Outcome(call: call, items: .success(items))
        case .failure(let error):
            return Outcome(call: call, items: .failure(Problem(error, code: error.reason.rawValue)))
        }
    }
}

import Core

public enum CostError: PlateError, Equatable {
    case unknownModel(String, known: [String])
    case limitReached(limit: Int, count: Int)

    public var what: String {
        switch self {
        case .unknownModel: "the model has no price"
        case .limitReached: "the daily call limit is reached"
        }
    }

    public var expected: String {
        switch self {
        case .unknownModel(_, let known): "one of \(known.joined(separator: ", "))"
        case .limitReached(let limit, _): "fewer than \(limit) calls today"
        }
    }

    public var saw: String {
        switch self {
        case .unknownModel(let model, _): model
        case .limitReached(_, let count): "\(count) calls"
        }
    }
}

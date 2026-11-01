import Foundation

/// Shared availability for C02 world/party/equipment facts. Missing APIs stay
/// `WAITING_SOURCE`; a present but unusable payload is `UNKNOWN`. Neither is success.
public enum WorldFactAvailability: String, Equatable {
    case ready
    case unknown = "UNKNOWN"
    case waitingSource = "WAITING_SOURCE"
}

/// Read-only `rpg.environment` snapshot. Weather/daypart/weekpart/season are
/// server strings only; a missing key is omitted, never filled with client weather.
public struct WorldEnvironmentProjection: Equatable {
    public static let keys = ["weather", "daypart", "weekpart", "season"]
    public enum Value: Equatable {
        case known(String)
        case unknown
        public var text: String {
            switch self { case .known(let value): return value; case .unknown: return "unknown" }
        }
    }
    public let availability: WorldFactAvailability
    public let values: [String: Value]
    public static let waitingSource = WorldEnvironmentProjection(availability: .waitingSource, values: [:])
    public static let unknown = WorldEnvironmentProjection(availability: .unknown, values: [:])
    public init(availability: WorldFactAvailability, values: [String: Value]) {
        self.availability = availability; self.values = values
    }
    /// Accepts a character card, `/api/play/rpg/status` body, or a bare environment object.
    public static func read(_ raw: PlayWireValue) -> Self {
        guard raw.object != nil else { return .unknown }
        let node = environmentNode(raw)
        if node == nil { return .waitingSource }
        guard let object = node?.object else { return .unknown }
        var values: [String: Value] = [:]
        for key in keys {
            guard let field = object[key], field != .null else { continue }
            values[key] = decode(field)
        }
        if values.isEmpty { return object.isEmpty ? .unknown : .init(availability: .ready, values: [:]) }
        return .init(availability: .ready, values: values)
    }
    public var weather: Value? { values["weather"] }
    public subscript(_ key: String) -> Value? { values[key] }
    private static func environmentNode(_ raw: PlayWireValue) -> PlayWireValue? {
        if raw["rpg"]["environment"] != .null { return raw["rpg"]["environment"] }
        if raw["environment"] != .null { return raw["environment"] }
        return nil
    }
    private static func decode(_ value: PlayWireValue) -> Value {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .unknown }
        return text == "unknown" ? .unknown : .known(text)
    }
}

import Foundation

/// Content capabilities this iOS build can render and finish, declared on `api/play/advanced/start`.
///
/// The server derives what a node needs from its frozen content (`ContentCapabilityRequirements`):
/// an undeclared client is let in unchecked, but a declared client must list every required key or
/// the start is refused with 409 before the player sees a screen it cannot use. This list is
/// therefore the complete set of what iOS supports today for an advanced-run start, built from
/// the same sources the UI renders from, so adding a play kit adds its declaration.
///
/// Only keys that can appear in an advanced-run requirement are listed: the node's play sections
/// (`game.*`, `role.views`, `hangman.pool`, `qa.letterPool`) and its station content
/// (`station.list`, `answer.*`, `sensor.*`, `media.*`, `location.gps`). Route-level keys
/// (`chapter.blocks*`, `route.branch`, `theme.runtime`, `game.teamCooperation`) belong to route
/// starts that iOS does not send a declaration for.
public enum PlayClientCapabilities {
    public static let version = 1
    public static let platform = "ios"

    /// Station-content keys iOS completes (`PlayNodeTask.resolve`, `PlayExperienceView`).
    static let station: [String] = [
        "station.list", "media.image", "media.audio", "media.photo", "location.gps",
        // validationMethod 0 / 5 arrive, 1 / 3 answer, 2 photo, 4 scan, 6 preference, 7 sensor
        "answer.arrive", "answer.gps", "answer.text", "answer.choice", "answer.photo", "answer.scan",
        "answer.preference", "answer.sensor",
        // 8 / 9 / 10 are finished by their same-named play kit (PlayKitScreen)
        "answer.estimate", "answer.pricePair", "answer.hiddenObject",
        // sensor subtypes PlayExperienceView handles: stillness stream and filtered photo
        "sensor.still", "sensor.filter_shot",
    ]
    /// Interaction features layered on renderers: letter pool input and role cards.
    static let features: [String] = ["hangman.pool", "qa.letterPool", "role.views"]

    /// `game.<section>` for every native play-kit renderer; server keys are the lower-cased section name.
    static var games: [String] { PlayKitScreenKind.allCases.map { "game." + $0.rawValue.lowercased() } }

    /// Every declared key, sorted and unique.
    public static var keys: [String] { Array(Set(station + features + games)).sorted() }

    /// `key@version` rows; the server accepts this as a JSON array.
    public static var tokens: [String] { keys.map { $0 + "@" + String(version) } }

    public static func declaration(_ keys: [String]) -> String {
        keys.sorted().map { $0 + "@" + String(version) }.joined(separator: ",")
    }

    /// Fields merged into the advanced start body.
    public static func startFields(clientVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) -> [String: PlayWireValue] {
        var fields: [String: PlayWireValue] = [
            "clientPlatform": .string(platform),
            "supportedCapabilities": .array(tokens.map { .string($0) }),
        ]
        if let clientVersion, !clientVersion.isEmpty { fields["clientVersion"] = .string(clientVersion) }
        return fields
    }
}

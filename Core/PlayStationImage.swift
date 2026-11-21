import Foundation

/// Which tier of the station image chain supplied the picture. `texture` means no image:
/// the view draws its designed dark surface, never a person placeholder or an empty area.
public enum PlayStationImageSource: String, Equatable {
    case game, station, chapter, route, texture
}

public struct PlayStationImage: Equatable {
    /// First usable image, nil only for `.texture`.
    public let source: String?
    public let tier: PlayStationImageSource
    public init(source: String?, tier: PlayStationImageSource) { self.source = source; self.tier = tier }
    public static let texture = PlayStationImage(source: nil, tier: .texture)
}

/// One shared station image chain (hengyin `utils/station-image.js` uses the same order):
/// station imgUrl → the station's chapter first image (img_arr) → route cover (topic imgUrl) → texture.
/// A game thumbnail tries the game cover first, then the same station chain.
/// F07: a later station's photo arrives as `imgUrl: null`, so it falls to the chapter or route
/// cover, both already public on the play screen; the hidden station photo is never revealed.
public enum PlayStationImageResolver {
    /// Comma/semicolon text, a JSON array string or an array. Malformed input yields `[]`.
    public static func list(_ raw: PlayWireValue?) -> [String] {
        guard let raw else { return [] }
        switch raw {
        case .string(let text): return list(text)
        case .array(let items):
            return items.flatMap { item -> [String] in
                if case .string(let text) = item { return splitPlain(text) }
                return []
            }
        default: return []
        }
    }

    public static func list(_ text: String?) -> [String] {
        guard let text else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(PlayWireValue.self, from: data),
               case .array = decoded {
                return list(decoded)
            }
            // Truncated JSON such as `["a.jpg",`: strip brackets and quotes, then split.
            let stripped = trimmed.filter { !"[]\"'".contains($0) }
            return splitPlain(stripped)
        }
        return splitPlain(trimmed)
    }

    public static func first(_ text: String?) -> String? { list(text).first }

    public static func station(stationImage: String?, chapterImages: [String], routeCover: String?) -> PlayStationImage {
        if let image = first(stationImage) { return .init(source: image, tier: .station) }
        if let image = chapterImages.first(where: { !$0.isEmpty }) { return .init(source: image, tier: .chapter) }
        if let image = first(routeCover) { return .init(source: image, tier: .route) }
        return .texture
    }

    public static func game(gameCover: String?, stationImage: String?, chapterImages: [String], routeCover: String?) -> PlayStationImage {
        if let image = first(gameCover) { return .init(source: image, tier: .game) }
        return station(stationImage: stationImage, chapterImages: chapterImages, routeCover: routeCover)
    }

    public static func station(for node: PlayNode, in result: PlayNodesResult) -> PlayStationImage {
        station(stationImage: node.imageURL, chapterImages: chapterImages(for: node, in: result), routeCover: result.topicCover)
    }

    /// `gameCover` defaults to the node's template story image; the play experience may
    /// pass the richer per-node extra when it has one.
    public static func game(for node: PlayNode, in result: PlayNodesResult, gameCover: String? = nil) -> PlayStationImage {
        game(gameCover: gameCover ?? node.storyImage, stationImage: node.imageURL,
             chapterImages: chapterImages(for: node, in: result), routeCover: result.topicCover)
    }

    static func chapterImages(for node: PlayNode, in result: PlayNodesResult) -> [String] {
        guard let chapterID = node.chapterID else { return [] }
        return result.chapters.first(where: { $0.id == chapterID })?.images ?? []
    }

    /// Own-origin images were historically stored as http://; upgrade only those two hosts,
    /// matching the mini program. Anything else stays as supplied (and non-https is not loaded).
    public static func secured(_ source: String) -> String {
        for host in ["chengyin-oss.oss-cn-shanghai.aliyuncs.com", "www.chengyinhub.com"] {
            let prefix = "http://" + host + "/"
            if source.lowercased().hasPrefix(prefix) { return "https://" + host + "/" + String(source.dropFirst(prefix.count)) }
        }
        return source
    }

    private static func splitPlain(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "null" && $0 != "undefined" }
    }
}

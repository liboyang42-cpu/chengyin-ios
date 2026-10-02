import Foundation

public struct SettingsAppInformation: Equatable {
    public let displayName: String?
    public let version: String?
    public let build: String?
    public init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let string = info[key] as? String else { return nil }
            let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !clean.contains("$(") else { return nil }
            return clean
        }
        displayName = value("CFBundleDisplayName") ?? value("CFBundleName")
        version = value("CFBundleShortVersionString")
        build = value("CFBundleVersion")
    }
    public static func current(bundle: Bundle = .main) -> Self { Self(info: bundle.infoDictionary ?? [:]) }
}
public struct SettingsSourceAttribution: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let sourceURL: String
    /// Exact Flutter settings-page attribution; retain offline. No third-party artwork is imported.
    public static let all: [Self] = [
        .init(id: "game-icons", title: "game-icons.net 游戏图标 · Creative Commons BY 3.0（要求署名）",
              detail: "作者：Delapouite、Lorc、Skoll、Sbed、Quoting、Lord Berandas", sourceURL: "https://game-icons.net/"),
        .init(id: "ansimuz", title: "像素城市场景 · Luis Zuno（ansimuz）· CC0 1.0",
              detail: "底图：Synth Cities、Warped City、Warped Miami Synth", sourceURL: "https://ansimuz.itch.io/")
    ]
}
public enum SettingsSourceContact {
    /// CN source only. Do not silently advertise this contact as a US support service.
    public static func phone(market: RegionalMarket?) -> String? { market == .china ? "15229020419" : nil }
}

/// AccountApi.playerCode source response contract. Not a local/generated QR. No service is
/// installed: the source POST can generate/reuse a personal code and needs reviewed access first.
public struct SettingsPlayerCode: Decodable, Equatable {
    public let imageURL: URL
    private enum CodingKeys: String, CodingKey { case qr }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .qr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw DecodingError.dataCorruptedError(forKey: .qr, in: container, debugDescription: "Personal-code image URL is unavailable or unsafe")
        }
        imageURL = url
    }
}
public enum SettingsUnavailableFeature: String, CaseIterable, Identifiable {
    case locationConsent, marketingConsent, accountDeletion
    public var id: String { rawValue }
    public var titleKey: String { "settingsNative.blocked.\(rawValue).title" }
    public var messageKey: String { "settingsNative.blocked.\(rawValue).message" }
}

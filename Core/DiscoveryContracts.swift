import Foundation

/// Read-only projections from the retained Flutter discovery models. No answers or draft fields.
public struct DiscoveryBanner: Decodable, Equatable, Identifiable {
    public let id: Int
    public let picUrl: String?
    public let linkType: Int
    public let dataId: String?
    public let contents: String?

    public enum Destination: Equatable { case activity(Int), topic(Int) }
    /// Feed only handles link types 3 and 4. Never open arbitrary H5 URLs from a banner.
    public var destination: Destination? {
        guard let text = dataId, let id = Int(text), id > 0 else { return nil }
        switch linkType { case 3: return .activity(id); case 4: return .topic(id); default: return nil }
    }
    enum CodingKeys: String, CodingKey { case id, picUrl, linkType, dataId, contents }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.discoveryID(.id)
        picUrl = try c.decodeIfPresent(String.self, forKey: .picUrl)
        linkType = try c.decodeIfPresent(Int.self, forKey: .linkType) ?? 0
        dataId = try c.decodeIfPresent(String.self, forKey: .dataId)
        contents = try c.decodeIfPresent(String.self, forKey: .contents)
    }
}

public struct DiscoveryCategory: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let type: Int?
    public let icon: String?
    enum CodingKeys: String, CodingKey { case id, categoryName, name, type, icon }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.discoveryID(.id)
        name = try c.decodeIfPresent(String.self, forKey: .categoryName)
            ?? c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decodeIfPresent(Int.self, forKey: .type)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
    }
}

public struct DiscoveryPlayTemplate: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let description: String?
    public let imgUrl: String?
    public let players: String?
    public let duration: Int?
    public let difficulty: String?
    public let usageLocation: String?
    public let requiredMaterials: String?
    public let categoryId: Int?
    public let ruleInstructions: String?
    public let storyText: String?
    public let storyImg: String?
    public let validationMethod: Int?
    public let questionName: String?
    public let publisher: String?
    public let status: Int?
    public let publishStatus: Int?
    public let useNum: Int?
    public let packType: Int

    public var durationMinutes: Int? { duration.flatMap { $0 > 0 ? $0 : nil } }
    public var playersText: String? {
        let value = discoveryNonempty(players)
        return value == "--" ? nil : value
    }
    /// Unknown pack values have no label, rather than being misrepresented as a known type.
    public var pack: DiscoveryPackType? { DiscoveryPackType(rawValue: packType) }
    public var verification: DiscoveryVerification? { validationMethod.map(DiscoveryVerification.init(code:)) }
    enum CodingKeys: String, CodingKey {
        case id, title, description, imgUrl, players, duration, difficulty, usageLocation
        case requiredMaterials, categoryId, ruleInstructions, storyText, storyImg
        case validationMethod, questionName, publisher, status, publishStatus, useNum, packType
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.discoveryID(.id)
        title = try c.decodeIfPresent(String.self, forKey: .title)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        imgUrl = try c.decodeIfPresent(String.self, forKey: .imgUrl)
        players = try c.discoveryScalarText(.players)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty)
        usageLocation = try c.decodeIfPresent(String.self, forKey: .usageLocation)
        requiredMaterials = try c.decodeIfPresent(String.self, forKey: .requiredMaterials)
        categoryId = try c.decodeIfPresent(Int.self, forKey: .categoryId)
        ruleInstructions = try c.decodeIfPresent(String.self, forKey: .ruleInstructions)
        storyText = try c.decodeIfPresent(String.self, forKey: .storyText)
        storyImg = try c.decodeIfPresent(String.self, forKey: .storyImg)
        validationMethod = try c.decodeIfPresent(Int.self, forKey: .validationMethod)
        questionName = try c.decodeIfPresent(String.self, forKey: .questionName)
        publisher = try c.discoveryScalarText(.publisher)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        publishStatus = try c.decodeIfPresent(Int.self, forKey: .publishStatus)
        useNum = try c.decodeIfPresent(Int.self, forKey: .useNum)
        guard useNum.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        packType = try c.decodeIfPresent(Int.self, forKey: .packType) ?? 0
    }
}

public enum DiscoveryPackType: Int, CaseIterable, Hashable { case single = 0, story = 1, shop = 2 }
public enum DiscoveryVerification: Equatable {
    case none, text, photo, choice, shopQR, gps, preferences, sensor, other
    public init(code: Int) {
        switch code {
        case 0: self = .none; case 1: self = .text; case 2: self = .photo
        case 3: self = .choice; case 4: self = .shopQR; case 5: self = .gps
        case 6: self = .preferences; case 7: self = .sensor; default: self = .other
        }
    }
}

/// A whole route template is a different entity from a one-location play template.
public struct DiscoveryTopicTemplate: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let subtitle: String
    public let chapterCount: Int
    public let locationCount: Int?
    /// Exact public catalog contract: nonnegative integral seconds, never minutes text.
    public let totalTime: Int?
    public let categoryIds: String
    public let previewOnly: Bool
    public let templateStatus: String?
    public let imgUrl: String?
    public var isVerified: Bool { templateStatus == "VERIFIED" }
    public func matchesCategory(_ id: Int?) -> Bool {
        guard let id else { return true }
        return categoryIds.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == String(id) }
    }
    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, chapterCount, locationCount, totalTime, categoryIds, previewOnly, templateStatus, imgUrl
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.discoveryID(.id)
        name = try c.discoveryScalarText(.name) ?? ""
        subtitle = try c.discoveryScalarText(.subtitle) ?? ""
        chapterCount = try c.decodeIfPresent(Int.self, forKey: .chapterCount) ?? 0
        locationCount = try PublicTemplateRouteCount.decode(from: c, forKey: .locationCount)
        totalTime = try c.decodeIfPresent(Int.self, forKey: .totalTime)
        guard totalTime.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        categoryIds = try c.discoveryScalarText(.categoryIds) ?? ""
        previewOnly = try c.decodeIfPresent(Bool.self, forKey: .previewOnly) ?? false
        templateStatus = try c.discoveryScalarText(.templateStatus)
        imgUrl = try c.discoveryScalarText(.imgUrl)
    }
}

/// Local name-only projection over an already authorized, loaded public catalog.
/// The catalog endpoint has no keyword/pagination contract; this grants no new read or write access.
public struct DiscoveryTopicTemplateNameSearch: Equatable {
    public let keyword: String
    public var isActive: Bool { !keyword.isEmpty }

    public init(_ text: String) {
        // Match the mini client's String.trim(), including BOM but excluding U+0085.
        let whitespace = CharacterSet(charactersIn:
            "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}"
            + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        keyword = text.trimmingCharacters(in: whitespace)
    }

    public func filter(_ rows: [DiscoveryTopicTemplate]) -> [DiscoveryTopicTemplate] {
        guard isActive else { return rows }
        let needle = keyword.lowercased()
        // Plain lowercase + literal substring, without locale, accent or width folding.
        // Filter before category grouping and retain server order, IDs and preview flags.
        return rows.filter { $0.name.lowercased().range(of: needle, options: .literal) != nil }
    }
}

public struct DiscoveryTemplateHome: Decodable, Equatable {
    public let total: Int?
    public let categories: [DiscoveryCategory]
    public let banner: [DiscoveryPlayTemplate]
    public let latest: [DiscoveryPlayTemplate]
    public let recommended: [DiscoveryPlayTemplate]
    public let mustPlay: [DiscoveryPlayTemplate]
    public let hot: [DiscoveryPlayTemplate]
    public var isEmpty: Bool { banner.isEmpty && latest.isEmpty && recommended.isEmpty && mustPlay.isEmpty && hot.isEmpty }
    enum CodingKeys: String, CodingKey { case total, categoryList, bannerList, latestList, recommendList, mustPlayList, hotList }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        categories = try c.decodeIfPresent([DiscoveryCategory].self, forKey: .categoryList) ?? []
        banner = try c.decodeIfPresent([DiscoveryPlayTemplate].self, forKey: .bannerList) ?? []
        latest = try c.decodeIfPresent([DiscoveryPlayTemplate].self, forKey: .latestList) ?? []
        recommended = try c.decodeIfPresent([DiscoveryPlayTemplate].self, forKey: .recommendList) ?? []
        mustPlay = try c.decodeIfPresent([DiscoveryPlayTemplate].self, forKey: .mustPlayList) ?? []
        hot = try c.decodeIfPresent([DiscoveryPlayTemplate].self, forKey: .hotList) ?? []
    }
}

public enum DiscoveryTemplateUnavailable: Error, Equatable {
    case notFound, deleted, underReview, offline, unknown
    public init(message: String?) {
        let message = message ?? ""
        if message.contains("审核中") { self = .underReview }
        else if message.contains("已下架") { self = .offline }
        else if message.contains("已删除") { self = .deleted }
        else if message.contains("不存在") { self = .notFound }
        else { self = .unknown }
    }
    public var retryable: Bool { self == .underReview || self == .unknown }
}

private func discoveryNonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}
private extension KeyedDecodingContainer {
    func discoveryID(_ key: Key) throws -> Int {
        let id = try decode(Int.self, forKey: key)
        guard id > 0 else { throw APIError.malformedResponse }
        return id
    }
    func discoveryScalarText(_ key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key), value.isFinite { return String(value) }
        throw APIError.malformedResponse
    }
}

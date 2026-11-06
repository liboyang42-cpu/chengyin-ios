import Foundation

/// Mini-program `pages/templatedetail` fields the base `DiscoveryPlayTemplate` does not
/// carry. Decoded from the same `api/template/info` / `api/template/myinfo` response so
/// the detail stays one read. Correct answers (`questionAnswer`) are never decoded.
public struct DiscoveryPlayTemplateExtras: Decodable, Equatable {
    /// Review feedback. Shown only for the viewer's own template (`scope=my`).
    public let reason: String?
    /// Server text (`CmsTemplateLibrary.rating` is a String); never computed on the client.
    public let rating: String?
    public let commentCount: Int?
    public let validationMethodText: String?
    /// Choice texts for the inert node preview (validation method 3).
    public let options: [Option]
    public let categoryNames: [String]
    public let imageURLs: [String]
    public let memberID: Int?
    public let productType: Int?
    public let chapterCount: String?
    public let locationCount: String?
    public let totalTime: String?

    public struct Option: Equatable, Hashable {
        public let key: String
        public let text: String
    }

    enum CodingKeys: String, CodingKey {
        case reason, rating, commentCount, validationMethodStr, questionA, questionB, questionC, questionD
        case sysCategoryList, imgUrls, memberId, productType, chapterCount, locationCount, nodeCount, gameCount, totalTime
    }
    private struct Category: Decodable { let categoryName: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reason = Self.text(try c.decodeIfPresent(String.self, forKey: .reason))
        rating = Self.text(try Self.scalar(c, .rating))
        let comments = try Self.scalar(c, .commentCount).flatMap { Int($0) }
        guard comments.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        commentCount = comments
        validationMethodText = Self.text(try c.decodeIfPresent(String.self, forKey: .validationMethodStr))
        var options: [Option] = []
        for (key, field) in [("A", CodingKeys.questionA), ("B", .questionB), ("C", .questionC), ("D", .questionD)] {
            if let value = Self.text(try c.decodeIfPresent(String.self, forKey: field)) { options.append(Option(key: key, text: value)) }
        }
        self.options = options
        categoryNames = (try c.decodeIfPresent([Category].self, forKey: .sysCategoryList) ?? []).compactMap { Self.text($0.categoryName) }
        imageURLs = Self.imageList(try? c.decodeIfPresent(String.self, forKey: .imgUrls), array: try? c.decodeIfPresent([String].self, forKey: .imgUrls))
        let member = try Self.scalar(c, .memberId).flatMap { Int($0) }
        memberID = member.flatMap { $0 > 0 ? $0 : nil }
        productType = try Self.scalar(c, .productType).flatMap { Int($0) }
        chapterCount = Self.text(try Self.scalar(c, .chapterCount))
        let locations = Self.text(try Self.scalar(c, .locationCount)), nodes = Self.text(try Self.scalar(c, .nodeCount))
        let games = Self.text(try Self.scalar(c, .gameCount))
        locationCount = locations ?? nodes ?? games
        totalTime = Self.text(try Self.scalar(c, .totalTime))
    }

    public init(reason: String? = nil, rating: String? = nil, commentCount: Int? = nil, validationMethodText: String? = nil,
                options: [Option] = [], categoryNames: [String] = [], imageURLs: [String] = [], memberID: Int? = nil,
                productType: Int? = nil, chapterCount: String? = nil, locationCount: String? = nil, totalTime: String? = nil) {
        self.reason = reason; self.rating = rating; self.commentCount = commentCount; self.validationMethodText = validationMethodText
        self.options = options; self.categoryNames = categoryNames; self.imageURLs = imageURLs; self.memberID = memberID
        self.productType = productType; self.chapterCount = chapterCount; self.locationCount = locationCount; self.totalTime = totalTime
    }

    /// `templatedetail.js isTopicTemplate`.
    public var isTopicTemplate: Bool { productType == 2 || chapterCount != nil || locationCount != nil }

    /// `templateDetail.js parseImgUrls`: JSON array, or comma/semicolon separated text.
    static func imageList(_ raw: String??, array: [String]??) -> [String] {
        if let array = array ?? nil { return array.compactMap(text) }
        guard let raw = raw ?? nil, let value = text(raw) else { return [] }
        if value.hasPrefix("["), let data = value.data(using: .utf8), let parsed = try? JSONDecoder().decode([String].self, from: data) {
            return parsed.compactMap(text)
        }
        return value.split(whereSeparator: { $0 == "," || $0 == ";" }).compactMap { text(String($0)) }
    }
    static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = TemplateDisplayText.decode(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func scalar(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String? {
        guard c.contains(key), try !c.decodeNil(forKey: key) else { return nil }
        if let value = try? c.decode(String.self, forKey: key) { return value }
        if let value = try? c.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? c.decode(Double.self, forKey: key), value.isFinite { return String(value) }
        throw APIError.malformedResponse
    }
}

/// `utils/display-text.js decodeDisplayFields`: the server stores `x<y` as `x&lt;y`.
public enum TemplateDisplayText {
    public static func decode(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = value
        for (entity, plain) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: plain)
        }
        return result
    }
}

/// The detail read: base projection plus the mini-program-only fields.
public struct DiscoveryPlayTemplateRead: Equatable {
    public let template: DiscoveryPlayTemplate
    public let extras: DiscoveryPlayTemplateExtras?
    public init(template: DiscoveryPlayTemplate, extras: DiscoveryPlayTemplateExtras?) { self.template = template; self.extras = extras }
}

/// Derived presentation, one place per mini-program helper.
public struct DiscoveryPlayTemplateDetailPresentation: Equatable {
    public enum Publisher: Equatable {
        case named(String, official: Bool)
        /// `scope=my` without a publisher name: 我的作品 (the nickname is not part of this read).
        case mine
        case creator
        /// Platform content: 城瘾 + 官方 badge.
        case platform
    }
    public enum StatKind: String, Equatable { case uses, rating, duration, chapters, nodes, totalTime }
    public struct Stat: Equatable { public let kind: StatKind; public let value: String }
    public enum NodePreview: Equatable {
        case text(question: String?)
        case choice(question: String?, options: [DiscoveryPlayTemplateExtras.Option])
        /// 该玩法验证方式为「X」，请报名参与活动后体验。 `nil` means 其他.
        case unsupported(methodText: String?)
    }

    public let publisher: Publisher
    public let reviewFeedback: String?
    public let stats: [Stat]
    public let ruleSteps: [String]
    public let verificationMethodText: String?
    public let questionText: String?
    public let sceneChips: [String]
    public let materialChips: [String]
    public let gallery: [String]
    public let rating: String?
    public let commentCount: Int?
    public let nodePreview: NodePreview?
    public let isTopicTemplate: Bool

    public init(_ read: DiscoveryPlayTemplateRead, ownScope: Bool) {
        let item = read.template, extras = read.extras ?? DiscoveryPlayTemplateExtras()
        let name = DiscoveryPlayTemplateExtras.text(item.publisher)
        let hasAuthor = extras.memberID != nil
        if let name { publisher = .named(name, official: !ownScope && !hasAuthor) }
        else if ownScope { publisher = .mine }
        else if hasAuthor { publisher = .creator }
        else { publisher = .platform }
        reviewFeedback = ownScope ? extras.reason : nil
        isTopicTemplate = extras.isTopicTemplate
        if isTopicTemplate {
            stats = [Stat(kind: .chapters, value: extras.chapterCount ?? ""), Stat(kind: .nodes, value: extras.locationCount ?? ""),
                     Stat(kind: .totalTime, value: extras.totalTime ?? item.durationMinutes.map(String.init) ?? "")].filter { !$0.value.isEmpty }
        } else {
            stats = [Stat(kind: .uses, value: item.useNum.map(String.init) ?? ""), Stat(kind: .rating, value: extras.rating ?? ""),
                     Stat(kind: .duration, value: item.durationMinutes.map(String.init) ?? "")].filter { !$0.value.isEmpty }
        }
        ruleSteps = (item.ruleInstructions ?? "").components(separatedBy: .newlines).compactMap(DiscoveryPlayTemplateExtras.text)
        verificationMethodText = extras.validationMethodText
        questionText = DiscoveryPlayTemplateExtras.text(item.questionName)
        sceneChips = extras.categoryNames + Self.splitValues(item.usageLocation)
        materialChips = Self.splitValues(item.requiredMaterials)
        var seen = Set<String>(), images: [String] = []
        for url in extras.imageURLs + [item.imgUrl, item.storyImg].compactMap(DiscoveryPlayTemplateExtras.text) where seen.insert(url).inserted { images.append(url) }
        gallery = images
        rating = extras.rating
        commentCount = extras.commentCount
        switch item.validationMethod {
        case nil, 0?: nodePreview = nil
        case 1?: nodePreview = .text(question: questionText)
        case 3?: nodePreview = .choice(question: questionText, options: extras.options)
        default: nodePreview = .unsupported(methodText: extras.validationMethodText)
        }
    }

    /// `templatedetail.js splitValues`.
    static func splitValues(_ text: String?) -> [String] {
        let separators = CharacterSet(charactersIn: "·、,，;；/")
        return (text ?? "").components(separatedBy: separators).compactMap(DiscoveryPlayTemplateExtras.text)
    }
}

/// Inert node preview sheet (节点交互预览). Nothing is sent and nothing is graded: 完成预览
/// only closes the sheet once an answer exists, exactly like `completePreview`.
public struct TemplateNodePreviewState: Equatable {
    public private(set) var answer = ""
    public private(set) var selectedOption: String?
    public let preview: DiscoveryPlayTemplateDetailPresentation.NodePreview
    public init(preview: DiscoveryPlayTemplateDetailPresentation.NodePreview) { self.preview = preview }
    public mutating func type(_ text: String) { answer = String(text.prefix(500)) }
    public mutating func select(_ key: String) {
        if case .choice(_, let options) = preview, options.contains(where: { $0.key == key }) { selectedOption = key }
    }
    public var canComplete: Bool {
        switch preview {
        case .text: return !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choice: return selectedOption != nil
        case .unsupported: return false
        }
    }
}

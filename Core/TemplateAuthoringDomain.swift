import Foundation

/// A play template is a single interaction. It is never a topic template, route or activity.
public struct AuthoringPlayTemplateID: RawRepresentable, Codable, Hashable {
    public let rawValue: Int
    public init?(rawValue: Int) { guard rawValue > 0 else { return nil }; self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer(); let raw = try c.decode(Int.self)
        guard let value = Self(rawValue: raw) else { throw TemplateAuthoringError.invalidContract }; self = value
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
public enum TemplateAuthoringJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([Self]), object([String: Self]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([Self].self) { self = .array(v) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v); case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    public var array: [Self]? { if case .array(let v) = self { return v }; return nil }
    public var bool: Bool { if case .bool(let v) = self { return v }; return false }
    public var number: Double? {
        if case .number(let v) = self { return v }
        if case .string(let v) = self { let s = v.trimmingCharacters(in: .whitespacesAndNewlines); return s.isEmpty ? 0 : Double(s) }
        return nil
    }
    public var integer: Int? { guard let v = number, v.isFinite, v.rounded() == v, v > Double(Int.min), v < Double(Int.max) else { return nil }; return Int(v) }
}
public enum TemplateAuthoringError: Error, Equatable {
    case invalidDraft, invalidContract, unavailable, changedSession, storageUnavailable, uncertain, staleReview
}
public enum TemplateAuthoringMethod: Int, Codable, CaseIterable, Identifiable {
    case manual = 0, text = 1, photo = 2, choice = 3, scan = 4, gps = 5
    public var id: Int { rawValue }
    public var labelKey: String { "templateAuthor.method.\(rawValue)" }
}
public struct TemplateStoryBeat: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var text = ""
    public var tag = ""
    public var imgs: [String] = []
    public init(text: String = "", tag: String = "", imgs: [String] = []) { self.text = text; self.tag = tag; self.imgs = imgs }
    public var wire: TemplateAuthoringJSON { .object(["text": .string(text), "tag": .string(tag), "imgs": .array(imgs.map { .string($0) })]) }
}
public struct TemplateAuthoringDraft: Codable, Equatable {
    public var id: AuthoringPlayTemplateID?
    public var originalTemplateID: AuthoringPlayTemplateID?
    public var title = ""
    public var description = ""
    public var isSync = 1
    public var finishEnabled = true
    public var validationMethod: TemplateAuthoringMethod = .manual
    public var photoReview = 0
    public var rewardEnabled = true
    public var storyEnabled = false
    public var voiceEnabled = false
    public var advanced = TemplateAdvancedDraft()
    public var imgUrl: String?
    public var players: String?
    public var difficulty: String?
    public var usageLocation: String?
    public var requiredMaterials: String?
    public var ruleInstructions: String?
    public var activityCategoryids: String?
    public var questionName: String?
    public var questionAnswer: String?
    public var questionA: String?
    public var questionB: String?
    public var questionC: String?
    public var questionD: String?
    public var correctAnswer: String?
    public var questionImg: String?
    public var questionAudio: String?
    public var questionOptionMediaJson: String?
    public var hint1: String?
    public var hint2: String?
    public var answerReveal: String?
    public var photoRequireDesc: String?
    public var feedbackText: String?
    public var medalImg: String?
    public var medalName: String?
    public var storyText: String?
    public var storyImg: String?
    public var storyJson: String?
    public var audioUrl: String?
    public var duration: Int?
    public var categoryId: Int?
    public var couponId: Int?
    public var audioDuration: Int?
    public init(title: String = "") { self.title = title }
    public var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var publishIssues: [String] {
        func blank(_ v: String?) -> Bool { (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var result: [String] = []
        func need(_ condition: Bool, _ key: String) { if !condition { result.append("templateAuthor.validation." + key) } }
        need(canSave, "title"); need(!blank(description), "description")
        // Dart String.length counts UTF-16 units, not user-perceived graphemes.
        need(description.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 30, "descriptionLength")
        need(!blank(players), "players"); need(duration.map { $0 > 0 } ?? false, "duration")
        need(!blank(activityCategoryids) || categoryId != nil, "category"); need(finishEnabled, "finish")
        if validationMethod == .text { need(!blank(questionName) && !blank(questionAnswer), "answer") }
        if validationMethod == .choice {
            need(!blank(questionName), "question")
            need([questionA, questionB, questionC, questionD].filter { !blank($0) }.count >= 2, "choices")
            need(!blank(correctAnswer), "correctAnswer")
            // Native safeguard: do not submit a correct option which was removed.
            let options = ["A": questionA, "B": questionB, "C": questionC, "D": questionD]
            need(options[correctAnswer ?? ""].map { !blank($0) } ?? false, "correctAnswer")
        }
        if rewardEnabled {
            need((couponId ?? 0) > 0 || !blank(feedbackText) || !blank(medalImg) || !blank(medalName), "reward")
            need(blank(medalImg) == blank(medalName), "medal")
        }
        if voiceEnabled { need(!blank(audioUrl), "audio") }
        if finishEnabled { result += advanced.issues }
        var unique: [String] = []; for key in result where !unique.contains(key) { unique.append(key) }; return unique
    }
    public mutating func setStory(_ beats: [TemplateStoryBeat]) throws {
        let rows = beats.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.imgs.isEmpty }.map(\.wire)
        storyJson = rows.isEmpty ? nil : String(data: try JSONEncoder().encode(rows), encoding: .utf8)
    }
    public func storyBeats() throws -> [TemplateStoryBeat] {
        guard let storyJson, !storyJson.isEmpty else { return [] }
        let rows = try JSONDecoder().decode([TemplateAuthoringJSON].self, from: Data(storyJson.utf8))
        return try rows.map { value in
            guard let row = value.object, let text = row["text"]?.string,
                  let tag = row["tag"]?.string, let images = row["imgs"]?.array else { throw TemplateAuthoringError.invalidContract }
            return try .init(text: text, tag: tag, imgs: images.map { guard let v = $0.string else { throw TemplateAuthoringError.invalidContract }; return v })
        }
    }
    /// Only public fields known in template_detail_page.dart are adopted. No answer reconstruction.
    public static func adopt(_ template: DiscoveryPlayTemplate) throws -> Self {
        guard let source = AuthoringPlayTemplateID(rawValue: template.id) else { throw TemplateAuthoringError.invalidContract }
        var d = Self(title: template.title); d.originalTemplateID = source
        d.description = template.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        d.imgUrl = template.imgUrl; d.players = template.players; d.duration = template.duration
        d.difficulty = template.difficulty; d.usageLocation = template.usageLocation
        d.requiredMaterials = template.requiredMaterials; d.ruleInstructions = template.ruleInstructions
        d.categoryId = template.categoryId
        return d
    }
}

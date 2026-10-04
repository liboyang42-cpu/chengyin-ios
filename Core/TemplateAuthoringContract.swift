import Foundation

/// Wire descriptors intentionally contain no host, credentials or network implementation.
public struct TemplateAuthoringRequest: Equatable, Codable {
    public enum Body: Equatable, Codable { case form([String: String]), json([String: TemplateAuthoringJSON]) }
    public let path: String
    public let method: String
    public let body: Body
    public let mutates: Bool
    public init(path: String, body: Body, mutates: Bool) { self.path = path; method = "POST"; self.body = body; self.mutates = mutates }
}
public enum TemplateAuthoringIntent: String, Codable, CaseIterable { case saveDraft, publish }
public enum TemplateAuthoringContract {
    public static func listMine() -> TemplateAuthoringRequest {
        .init(path: "/api/template/my-list", body: .form(["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "100"]), mutates: false)
    }
    public static func libraryStatus(id: AuthoringPlayTemplateID, current: Int?) -> TemplateAuthoringRequest {
        .init(path: "/api/template/updateLibraryStatus", body: .form(["template_id": String(id.rawValue), "publish_status": current == 1 ? "0" : "1"]), mutates: true)
    }
    public static func remove(id: AuthoringPlayTemplateID) -> TemplateAuthoringRequest {
        .init(path: "/api/template/delete", body: .form(["template_id": String(id.rawValue)]), mutates: true)
    }
    public static func dictionary(_ type: String) throws -> TemplateAuthoringRequest {
        guard ["app_template_difficulty", "app_template_duration", "app_template_players"].contains(type) else { throw TemplateAuthoringError.invalidContract }
        return .init(path: "/api/common/dict", body: .form(["dictType": type]), mutates: false)
    }
    public static func request(_ draft: TemplateAuthoringDraft, intent: TemplateAuthoringIntent) throws -> TemplateAuthoringRequest {
        guard draft.canSave, intent != .publish || draft.publishIssues.isEmpty else { throw TemplateAuthoringError.invalidDraft }
        return .init(path: intent == .saveDraft ? "/api/template/draft" : "/api/template/publish", body: .json(try payload(draft)), mutates: true)
    }
    public static func payload(_ d: TemplateAuthoringDraft) throws -> [String: TemplateAuthoringJSON] {
        var p: [String: TemplateAuthoringJSON] = ["title": .string(d.title.trimmingCharacters(in: .whitespacesAndNewlines)), "description": .string(d.description.trimmingCharacters(in: .whitespacesAndNewlines)), "isSync": .number(Double(d.isSync))]
        func string(_ name: String, _ value: String?) { if let value { p[name] = .string(value) } }
        func number(_ name: String, _ value: Int?) { if let value { p[name] = .number(Double(value)) } }
        number("id", d.id?.rawValue); number("originalTemplateId", d.originalTemplateID?.rawValue)
        number("categoryId", d.categoryId); number("duration", d.duration)
        string("imgUrl", d.imgUrl); string("players", d.players); string("usageLocation", d.usageLocation)
        string("requiredMaterials", d.requiredMaterials); string("difficulty", d.difficulty)
        string("ruleInstructions", d.ruleInstructions); string("activityCategoryids", d.activityCategoryids)
        if d.finishEnabled {
            p["validationMethod"] = .number(Double(d.validationMethod.rawValue))
            if d.validationMethod == .text || d.validationMethod == .choice {
                string("questionName", d.questionName); string("questionImg", d.questionImg); string("questionAudio", d.questionAudio)
            }
            if d.validationMethod == .text { string("questionAnswer", d.questionAnswer) }
            if d.validationMethod == .choice {
                string("questionA", d.questionA); string("questionB", d.questionB); string("questionC", d.questionC); string("questionD", d.questionD)
                string("correctAnswer", d.correctAnswer); string("questionOptionMediaJson", d.questionOptionMediaJson)
            }
            if [.text, .choice, .gps].contains(d.validationMethod) { string("hint1", d.hint1); string("hint2", d.hint2); string("answerReveal", d.answerReveal) }
            if d.validationMethod == .photo { string("photoRequireDesc", d.photoRequireDesc); number("photoReview", d.photoReview) }
            let raw = try d.advanced.serialize(); if !raw.isEmpty { p["advancedConfigJson"] = .string(raw) }
        }
        if d.rewardEnabled { string("feedbackText", d.feedbackText); number("couponId", d.couponId); string("medalImg", d.medalImg); string("medalName", d.medalName)
            if !(d.medalName ?? "").isEmpty || !(d.medalImg ?? "").isEmpty { string("medalStyle", d.medalStyle) }
        }
        if d.storyEnabled { string("storyText", d.storyText); string("storyImg", d.storyImg); string("storyJson", d.storyJson) }
        if d.voiceEnabled { string("audioUrl", d.audioUrl); number("audioDuration", d.audioDuration) }
        return p
    }
    public static func decodeList(_ data: Data, httpStatus: Int) throws -> [DiscoveryPlayTemplate] {
        try requireSuccess(data, httpStatus: httpStatus)
        let body = try JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: data)
        guard let rows = body["data"]?.array ?? body["data"]?.object?["rows"]?.array else { throw TemplateAuthoringError.invalidContract }
        return try JSONDecoder().decode([DiscoveryPlayTemplate].self, from: JSONEncoder().encode(rows))
    }
    public static func requireSuccess(_ data: Data, httpStatus: Int) throws {
        if httpStatus == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(httpStatus) else { throw APIError.httpStatus(httpStatus) }
        let body = try JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: data)
        guard let code = body["code"]?.integer else { throw TemplateAuthoringError.invalidContract }
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw TemplateAuthoringRejection(message: body["msg"]?.string ?? "", code: code) }
    }
}
public struct TemplateAuthoringRejection: Error, Equatable {
    public let message: String
    public let code: Int
    public var duplicateName: Bool { message.contains("已存在") }
    public var contentRejected: Bool { !message.contains("网络") && !message.contains("稍后重试") && ["违规", "敏感", "不合规", "含有"].contains(where: message.contains) }
    public var messageKey: String { duplicateName ? "templateAuthor.duplicateName" : contentRejected ? "templateAuthor.contentRejected" : "templateAuthor.rejected" }
}
public struct TemplateAuthoringDictionaryOption: Equatable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }
    /// Source fallback values are index strings; display labels remain source data.
    public static func fallback(_ type: String) -> [Self] {
        let labels = ["app_template_difficulty": ["简易", "一般", "困难"], "app_template_duration": ["10min", "16min", "20min", "23min"], "app_template_players": ["1-2 人", "3-5 人", "6 人以上"]][type] ?? []
        return labels.enumerated().map { .init(value: String($0.offset), label: $0.element) }
    }
}

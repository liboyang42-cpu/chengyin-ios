import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PublishingProject: Identifiable, Codable, Equatable {
    public let resource: PublishedResource
    public let title: String
    public let state: String
    public let stateText: String?
    public let publishStatus: String?
    public let ownerType: String?
    public let signupCount: Int
    public let raw: [String: ProjectEditJSON]
    public var id: String { "\(resource.kind.rawValue):\(resource.value)" }
    public init(_ body: [String: ProjectEditJSON]) throws {
        guard let kind = PublishedResource.Kind(rawValue: body["bizType"]?.text ?? ""), let id = body["id"]?.integer else { throw PublishModesError.invalidContract }
        resource = try PublishedResource(kind: kind, value: id); raw = body; title = body["title"]?.text ?? ""
        state = body["state"]?.text ?? ""; stateText = body["stateText"]?.text; publishStatus = body["publishStatus"]?.text
        ownerType = body["ownerType"]?.text; signupCount = body["signupCount"]?.integer ?? 0
    }
    public var online: Bool { publishStatus == "online" || ["running", "notStarted"].contains(state) }
    public var canToggle: Bool { ["running", "notStarted", "offline"].contains(state) }
    public var canDelete: Bool { signupCount <= 0 && ["draft", "offline", "rejected", "completed"].contains(state) }
    public var canCancelWithRefund: Bool {
        guard canToggle else { return false }
        switch resource.kind { case .topic: return ownerType != "club"; case .activity: return ownerType != "merchant" && signupCount > 0; case .template: return false }
    }
}
public struct PublishingProjectPage: Equatable {
    public let rows: [PublishingProject]
    public let unknownRows: [[String: ProjectEditJSON]]
    public let total: Int
    public var truncated: Bool { total > rows.count + unknownRows.count }
}
public struct PublishingOption: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let detail: String
    public init(id: Int, name: String, detail: String = "") { self.id = id; self.name = name; self.detail = detail }
}
/// A request descriptor contains no host or credentials. Mutation descriptors alone cannot dispatch.
public struct PublishingRequest: Codable, Equatable {
    public enum Encoding: String, Codable { case json, form, none }
    public let path: String
    public let encoding: Encoding
    public let fields: [String: ProjectEditJSON]
    public init(path: String, encoding: Encoding, fields: [String: ProjectEditJSON] = [:]) { self.path = path; self.encoding = encoding; self.fields = fields }
}
public enum PublishingRead: Equatable {
    case capability, identityStatus, categories(activity: Bool), collaborators(keyword: String), templates(keyword: String, scope: String)
    case projects(type: String, state: String, ownerType: String, scope: String, pageSize: Int)
    case aiQuota
    public var request: PublishingRequest {
        switch self {
        case .capability: return .init(path: "api/publish/home", encoding: .json)
        case .identityStatus: return .init(path: "api/publisher/identity/status", encoding: .json)
        case .categories(let activity): return .init(path: "api/category/list", encoding: .form, fields: ["parentid": .string("0"), "type": .string(activity ? "2" : "1")])
        case .collaborators(let keyword):
            var f: [String: ProjectEditJSON] = ["user_type": .string("0")]; if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { f["keyword"] = .string(keyword.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return .init(path: "api/user/list", encoding: .form, fields: f)
        case .templates(let keyword, let scope):
            var f: [String: ProjectEditJSON] = ["is_quote": .string("1"), "scope": .string(scope)]
            if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { f["keyword"] = .string(keyword.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return .init(path: "api/template/my-list", encoding: .form, fields: f)
        case .projects(let type, let state, let owner, let scope, let size):
            var f: [String: ProjectEditJSON] = ["type": .string(type), "state": .string(state), "ownerType": .string(owner), "pageNum": .string("1"), "pageSize": .string(String(size))]
            if !scope.isEmpty { f["scope"] = .string(scope) }; return .init(path: "api/project/my", encoding: .form, fields: f)
        case .aiQuota: return .init(path: "api/ai/theme/draft/quota", encoding: .none)
        }
    }
}
public enum PublishingProjectAction: String, Codable { case remove, toggle }
public enum PublishingContracts {
    public static func activity(_ draft: ActivityPublishDraft) throws -> PublishingRequest { .init(path: "api/activity/publish", encoding: .json, fields: try draft.wire()) }
    /// Historical API only. Current quick-create UI uses professionalSeed, never this request.
    public static func legacySimple(name: String, description: String) -> PublishingRequest {
        .init(path: "api/topic/create", encoding: .json, fields: ["name": .string(name), "description": .string(description), "publishMode": .string("simple")])
    }
    public static func project(_ project: PublishingProject, action: PublishingProjectAction) throws -> PublishingRequest {
        guard (action == .remove ? project.canDelete : project.canToggle) else { throw PublishModesError.forbidden }
        let path: String
        switch (project.resource.kind, action) {
        case (.topic, .remove): path = "api/topic/delete"
        case (.topic, .toggle): path = "api/topic/update_user_status"
        case (.activity, .remove): path = "api/activity/delete"
        case (.activity, .toggle): path = "api/activity/update_publish_status"
        case (.template, .remove): path = "api/template/delete"
        case (.template, .toggle): path = "api/template/updateLibraryStatus"
        }
        var f: [String: ProjectEditJSON] = ["id": .string(String(project.resource.value))]
        if project.resource.kind == .topic && action == .toggle { f["expectedUserStatus"] = .string(project.online ? "1" : "0") }
        return .init(path: path, encoding: .form, fields: f)
    }
    public static func aiThemeDraft(idea: String) -> PublishingRequest { .init(path: "api/ai/theme/draft", encoding: .json, fields: ["idea": .string(idea.trimmingCharacters(in: .whitespacesAndNewlines))]) }
    public static func aiClubDesign(idea: String, style: String?, minutes: Int?) -> PublishingRequest {
        var f: [String: ProjectEditJSON] = ["idea": .string(idea.trimmingCharacters(in: .whitespacesAndNewlines))]
        if let style { f["clubStyle"] = .string(style) }; if let minutes { f["targetDurationMin"] = .number(Decimal(minutes)) }
        return .init(path: "api/ai/club/design", encoding: .json, fields: f)
    }
    /// Shares the source contract with TemplateAuthoring; no provider execution path.
    public static func aiTemplateFill(shopName: String, extraNote: String, category: String = "", reward: String = "", playStyle: String = "", validationMethod: Int? = nil) -> PublishingRequest {
        var fields: [String: ProjectEditJSON] = ["shopName": .string(shopName), "category": .string(category), "reward": .string(reward), "playStyle": .string(playStyle), "extraNote": .string(extraNote)]
        if let validationMethod { fields["validationMethod"] = .number(Decimal(validationMethod)) }
        return .init(path: "api/ai/template/fill", encoding: .json, fields: fields)
    }
    public static func safetyPrecheck(_ fields: [String: ProjectEditJSON]) -> PublishingRequest { .init(path: "api/ai/safety/precheck", encoding: .json, fields: fields) }
    public static func decodeProjects(_ value: ProjectEditJSON) throws -> PublishingProjectPage {
        guard let object = value.object, let rows = object["rows"]?.array else { throw PublishModesError.invalidContract }
        var known: [PublishingProject] = []; var unknown: [[String: ProjectEditJSON]] = []
        for row in rows { guard let raw = row.object else { throw PublishModesError.invalidContract }; if let project = try? PublishingProject(raw) { known.append(project) } else { unknown.append(raw) } }
        let total = object["total"]?.integer ?? Int(object["total"]?.text ?? "") ?? rows.count
        return .init(rows: known, unknownRows: unknown, total: max(0, total))
    }
    public static func options(_ value: ProjectEditJSON, kind: PublishingRead) throws -> [PublishingOption] {
        let raw: [ProjectEditJSON]?
        switch kind { case .categories: raw = value.array; default: raw = value.object?["rows"]?.array }
        guard let raw else { throw PublishModesError.invalidContract }
        return raw.compactMap { row in
            guard let o = row.object, let id = o["id"]?.integer, id > 0 else { return nil }
            switch kind {
            case .collaborators: return .init(id: id, name: o["nickname"]?.text ?? "", detail: o["followNum"]?.text ?? o["followNum"]?.integer.map(String.init) ?? "—")
            default: return .init(id: id, name: o["categoryName"]?.text ?? o["name"]?.text ?? o["title"]?.text ?? "")
            }
        }
    }
}
/// China source identity rules. No international ID validator is inferred or provided.
public enum PublishingIdentity {
    public static func normalize(_ value: String) -> String { value.components(separatedBy: .whitespacesAndNewlines).joined().uppercased() }
    public static func validChinaID(_ input: String, currentYear: Int) -> Bool {
        let value = normalize(input); let chars = Array(value)
        guard currentYear >= 1900, value.range(of: #"^[0-9]{17}[0-9X]$"#, options: .regularExpression) != nil,
              let year = Int(String(chars[6...9])), (1900...currentYear).contains(year), let month = Int(String(chars[10...11])), (1...12).contains(month), let day = Int(String(chars[12...13])) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { return false }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let sum = (0..<17).reduce(0) { $0 + (chars[$1].wholeNumberValue ?? 0) * weights[$1] }
        return Array("10X98765432")[sum % 11] == chars[17]
    }
    /// Ephemeral descriptor only; this module has no identity dispatch or persistence path.
    public static func registration(name: String, idCard: String, consent: Bool, source: String, region: PublishingRegion, registered: Bool, currentYear: Int) throws -> PublishingRequest {
        guard region == .china else { throw PublishModesError.unavailable }
        guard !registered, ["club_apply", "merchant_apply", "topic_publish"].contains(source) else { throw PublishModesError.forbidden }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(name.utf16.count), name.range(of: "[0-9]", options: .regularExpression) == nil, validChinaID(idCard, currentYear: currentYear), consent else { throw PublishModesError.invalidDraft }
        return .init(path: "api/publisher/identity", encoding: .json, fields: ["realName": .string(name), "idCard": .string(normalize(idCard)), "consent": .bool(true), "source": .string(source)])
    }
}

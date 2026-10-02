import Foundation

public enum MerchantOperationsDocument: Equatable {
    case draft(MerchantOperationsDraft)
    case cityNodes(MerchantCityCatalog)
    case templates([MerchantTemplateRecord])
    case assets(MerchantAssetResources)
}
public enum MerchantOperationsDraft: Equatable {
    case profile(MerchantStoreProfile), decor(MerchantStoreDecor), gallery(MerchantStoreDecor)
    case story(MerchantStorefront), cooperation(MerchantCoopSettings), character(MerchantStoreCharacter)
    case template(MerchantNodeTemplate)
    public var destination: MerchantOperationsDestination {
        switch self {
        case .profile: return .profile; case .decor: return .decor; case .gallery: return .gallery
        case .story: return .story; case .cooperation: return .cooperation; case .character: return .character
        case .template(let draft): return .template(draft.id)
        }
    }
    public var blocker: String? {
        switch self {
        case .profile: return nil // Source profile form imposes no new length/URL constraints.
        case .decor(let value): return value.blocker
        case .gallery(let value): return value.gallery.count > 9 ? "merchant.operations.galleryLimit" : nil
        case .story(let value): return value.profile.description.utf16.count > 300 ? "merchant.operations.storyLimit" : nil
        case .cooperation(let value): return value.blocker
        case .character(let value): return value.blocker
        case .template(let value): return value.blocker
        }
    }
    /// Exact source JSON contracts used by previews and the dormant scoped transport.
    /// Story intentionally remains two operations: the source is not atomic.
    public func previews() throws -> [MerchantOperationsRequestPreview] {
        if blocker != nil { throw APIError.invalidRequest }
        switch self {
        case .profile(let value): return [try .init(path: "api/merchant/update", fields: value.fields)]
        case .decor(let value): return [try .init(path: "api/merchant/decor/save", fields: value.fields())]
        case .gallery(let value): return [try .init(path: "api/merchant/decor/save", fields: ["gallery": MerchantStoreDecor.listString(value.gallery)])]
        case .story(let value): return [try .init(path: "api/merchant/decor/save", fields: ["storyTitle": value.decor.storyTitle.trimmingCharacters(in: .whitespacesAndNewlines)]), try .init(path: "api/merchant/update", fields: value.profile.fields)]
        case .cooperation(let value): return [try .init(path: "api/merchant/coop-profile/save", fields: value.fields)]
        case .character(let value): return [try .init(path: "api/merchant/npc/save", fields: value.fields)]
        case .template(let value): return [try .init(path: "api/merchant/city-node/template/submit", fields: value.fields)]
        }
    }
}
public struct MerchantOperationsRequestPreview: Equatable {
    public let path: String
    public let json: Data
    public init(path: String, fields: [String: Any]) throws {
        self.path = path; json = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
}
public enum MerchantOperationsFailure: Error, Equatable {
    case liveWritesDisabled, accessDenied, notSent, outcomeUnknown, partial(acknowledgedSteps: Int), rejected(code: Int, message: String?)
}
public enum MerchantOperationsIssue: Equatable {
    case key(String), server(String)
    public init(_ error: Error) {
        if error as? APIError == .unauthorized { self = .key("merchant.operations.signedOut") }
        else if error as? APIError == .notConfigured { self = .key("auth.notConfigured") }
        else if error as? APIError == .malformedResponse { self = .key("merchant.invalidResponse") }
        else if error as? MerchantOperationsFailure == .accessDenied { self = .key("merchant.access.denied") }
        else if error as? MerchantOperationsFailure == .liveWritesDisabled { self = .key("merchant.operations.liveDisabled") }
        else if let failure = error as? MerchantOperationsFailure, case .rejected(_, let message) = failure, let message, !message.isEmpty { self = .server(message) }
        else { self = .key("merchant.operations.loadFailed") }
    }
}

public struct MerchantOperationsReviewLine: Identifiable, Equatable {
    public let key: String
    public let value: String
    public var id: String { key }
    public init(_ key: String, _ value: String) { self.key = "merchant.operations." + key; self.value = value }
}
extension MerchantOperationsDraft {
    /// Human-readable frozen content. This does not turn a local draft into approval or publication.
    public var reviewLines: [MerchantOperationsReviewLine] {
        switch self {
        case .profile(let v): return [.init("name", v.name), .init("description", v.description), .init("derivatives", v.derivatives), .init("website", v.website), .init("preference", v.preference)]
        case .decor(let v): return [.init("slogan", v.slogan), .init("cityRole", v.cityRole), .init("tags", v.tags.joined(separator: "; "))]
        case .gallery(let v): return [.init("galleryCount", String(v.gallery.count))]
        case .story(let v): return [.init("storyBody", v.profile.description)]
        case .cooperation(let v): return [.init("capacity", v.capacity), .init("availableTime", v.availableTime), .init("chargeType", v.chargeType.map(String.init) ?? "—"), .init("demand", v.demand)]
        case .character(let v): return [.init("name", v.name), .init("greeting", v.greeting), .init("persona", v.persona), .init("knowledge", v.knowledge)]
        case .template(let v):
            var lines = [MerchantOperationsReviewLine("titleField", v.title), .init("description", v.description)]
            if v.method == .secretWord { lines.append(.init("answer", v.questionAnswer)) }
            if v.method == .quiz { lines += [.init("question", v.questionName), .init("optionA", v.optionA), .init("optionB", v.optionB), .init("optionC", v.optionC), .init("optionD", v.optionD), .init("correctAnswer", v.correctAnswer)] }
            lines.append(.init("feedback", v.feedbackText)); return lines
        }
    }
}

public struct MerchantOperationsAcknowledgment: Equatable {
    public let acknowledgedSteps: Int
    public let templateID: Int?
    public let message: String?
}
public extension MerchantOperationsDestination {
    /// Story writes overlap both profile and decor. One conservative lock prevents replay
    /// through another editor after a partial write, without persisting any document content.
    var pendingTarget: String {
        switch self {
        case .profile, .decor, .gallery, .story: return "merchant:storefront"
        default: return "merchant:" + id
        }
    }
}

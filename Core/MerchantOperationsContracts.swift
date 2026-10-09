import Foundation

/// Additional access/me projection. Existing MerchantAccess remains the identity authority.
public struct MerchantOperationsAccess: Decodable, Equatable {
    public let identity: MerchantAccess
    public let profileWrite: Bool
    public let cooperationManage: Bool
    private enum CodingKeys: String, CodingKey { case permissions }
    public init(from decoder: Decoder) throws {
        identity = try MerchantAccess(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        profileWrite = identity.active && permissions.contains("merchant:profile:write")
        cooperationManage = identity.active && permissions.contains("merchant:coop:manage")
    }
    public func allows(_ destination: MerchantOperationsDestination) -> Bool {
        guard identity.active else { return false }
        switch destination {
        case .npcMapPoint: return profileWrite && cooperationManage
        case .businessStatus: return profileWrite && identity.allows(.basicRead)
        case .profile, .decor, .gallery, .story: return profileWrite
        case .character: return profileWrite
        case .cooperation: return cooperationManage
        case .templates, .template: return identity.allows(.projects)
        // Legacy resource and city-node reads retain their existing policy.
        // The current NPC editor instead requires the explicit PROFILE_WRITE grant.
        case .assets, .cityNodes: return true
        }
    }
}
public enum MerchantOperationsDestination: Hashable, Identifiable {
    case businessStatus, profile, decor, gallery, story, cooperation, character, npcMapPoint, assets, cityNodes, templates, template(Int?)
    public var id: String {
        switch self {
        case .template(let id): return "template:\(id.map(String.init) ?? "new")"
        default: return titleKey
        }
    }
    public var titleKey: String {
        switch self {
        case .npcMapPoint: return "merchantMapPoint.title"
        case .businessStatus: return "merchant.operations.businessStatus"
        case .profile: return "merchant.operations.profile"
        case .decor: return "merchant.operations.decor"
        case .gallery: return "merchant.operations.gallery"
        case .story: return "merchant.operations.story"
        case .cooperation: return "merchant.operations.cooperation"
        case .character: return "merchant.operations.character"
        case .assets: return "merchant.operations.assets"
        case .cityNodes: return "merchant.operations.cityNodes"
        case .templates: return "merchant.operations.templates"
        case .template: return "merchant.operations.template"
        }
    }
}

public struct MerchantStoreProfile: Decodable, Equatable {
    public var id: Int?
    public var logo: String
    public var name: String
    public var description: String
    public var derivatives: String
    /// Distinct from legacy merchandise; nil means absent/null and must not clear it.
    public var derivativeBenefits: String?
    /// Original opaque server value; unrelated edits never resend it.
    public let businessTime: String?
    public var businessTimeReplacement: String? = nil
    public var displayedBusinessTime: String? { businessTimeReplacement ?? businessTime }
    public var website: String
    public var preference: String
    private enum CodingKeys: String, CodingKey { case id, logo, name, description, derivatives, derivativeBenefits, businessTime, website, preference }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard !c.allKeys.isEmpty else { throw APIError.malformedResponse }
        id = c.merchantInteger(.id)
        logo = try c.decodeIfPresent(String.self, forKey: .logo) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        derivatives = try c.decodeIfPresent(String.self, forKey: .derivatives) ?? ""
        derivativeBenefits = try c.decodeIfPresent(String.self, forKey: .derivativeBenefits)
        businessTime = try c.decodeIfPresent(String.self, forKey: .businessTime)
        website = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
        preference = try c.decodeIfPresent(String.self, forKey: .preference) ?? ""
    }
    public var benefitsBlocker: String? {
        (derivativeBenefits?.utf16.count ?? 0) > 100 ? "merchant.operations.benefitsLimit" : nil
    }
    /// Existing fields plus the source's optional derivativeBenefits patch. No contact/status fields.
    public var fields: [String: Any] {
        var fields = legacyFields
        if let derivativeBenefits { fields["derivativeBenefits"] = derivativeBenefits }
        if let businessTimeReplacement { fields["businessTime"] = businessTimeReplacement }
        return fields
    }
    public var hoursBlocker: String? {
        guard let businessTimeReplacement else { return nil }
        return MerchantStoreHours(wireValue: businessTimeReplacement) == nil ? "merchant.operations.hoursInvalid" : nil
    }
    /// Story editing must not start resubmitting the independently edited benefits field.
    public var legacyFields: [String: Any] {
        ["logo": logo, "name": name, "description": description, "derivatives": derivatives,
         "website": website, "preference": preference]
    }
}

public struct MerchantStoreDecor: Decodable, Equatable {
    public var coverImage: String?
    public var slogan: String
    public var cityRole: String
    public var storyTitle: String
    public var gallery: [String]
    public var tags: [String]
    public var categoryID: Int?
    public var featuredType: Int?
    public var featuredID: Int?
    public var serviceTag: String?
    public var serviceText: String?
    public var locationLat: Double?
    public var locationLng: Double?
    public var locationVerified: Int?
    private enum CodingKeys: String, CodingKey {
        case coverImage, slogan, cityRole, storyTitle, gallery, tags, categoryId, featuredType, featuredId
        case serviceTag, serviceText, locationLat, locationLng, locationVerified
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coverImage = try c.decodeIfPresent(String.self, forKey: .coverImage)
        slogan = try c.decodeIfPresent(String.self, forKey: .slogan) ?? ""
        cityRole = try c.decodeIfPresent(String.self, forKey: .cityRole) ?? ""
        storyTitle = try c.decodeIfPresent(String.self, forKey: .storyTitle) ?? ""
        gallery = try Self.list(c, .gallery); tags = try Self.list(c, .tags)
        categoryID = c.merchantInteger(.categoryId); featuredType = c.merchantInteger(.featuredType); featuredID = c.merchantInteger(.featuredId)
        serviceTag = try c.decodeIfPresent(String.self, forKey: .serviceTag)
        serviceText = try c.decodeIfPresent(String.self, forKey: .serviceText)
        locationLat = Self.number(c, .locationLat); locationLng = Self.number(c, .locationLng)
        locationVerified = c.merchantInteger(.locationVerified)
    }
    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        let number = (try? c.decode(Double.self, forKey: key)) ?? (try? c.decode(String.self, forKey: key)).flatMap(Double.init)
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
    private static func list(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [String] {
        if !c.contains(key) { return [] }
        if try c.decodeNil(forKey: key) { return [] }
        let values: [String]
        if let list = try? c.decode([String].self, forKey: key) { values = list }
        else {
            let raw = try c.decode(String.self, forKey: key)
            if let list = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) { values = list }
            else { values = raw.components(separatedBy: ";") }
        }
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    public var blocker: String? {
        if gallery.count > 9 { return "merchant.operations.galleryLimit" }
        if ((featuredType ?? 0) > 0) != ((featuredID ?? 0) > 0) { return "merchant.operations.featuredIncomplete" }
        if (coverImage ?? "").isEmpty && slogan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cityRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && storyTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && gallery.isEmpty && tags.isEmpty { return "merchant.operations.decorEmpty" }
        return nil
    }
    /// This full payload is a contract preview only; no production send exists.
    public func fields() throws -> [String: Any] {
        ["coverImage": coverImage as Any? ?? NSNull(), "slogan": slogan.trimmingCharacters(in: .whitespacesAndNewlines),
         "cityRole": cityRole.trimmingCharacters(in: .whitespacesAndNewlines), "storyTitle": storyTitle.trimmingCharacters(in: .whitespacesAndNewlines),
         "gallery": try Self.listString(gallery), "tags": try Self.listString(tags),
         "categoryId": categoryID as Any? ?? NSNull(), "featuredType": featuredType as Any? ?? NSNull(),
         "featuredId": featuredID as Any? ?? NSNull(), "serviceTag": serviceTag as Any? ?? NSNull(),
         "serviceText": serviceText as Any? ?? NSNull(), "locationLat": locationLat as Any? ?? NSNull(),
         "locationLng": locationLng as Any? ?? NSNull(), "locationVerified": locationVerified as Any? ?? NSNull()]
    }
    public static func listString(_ values: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }
}
public struct MerchantCoopSettings: Decodable, Equatable {
    public var capacity: String
    public var availableTime: String
    public var chargeType: Int?
    public var demand: String
    /// Hidden in this form and preserved across the six-field overwrite contract.
    public let suitActivityTypes: String?
    public let coopOpen: Int?
    private enum CodingKeys: String, CodingKey { case capacity, availableTime, chargeType, demand, suitActivityTypes, coopOpen }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        capacity = (try? c.decode(String.self, forKey: .capacity)) ?? c.merchantInteger(.capacity).map(String.init) ?? ""
        availableTime = try c.decodeIfPresent(String.self, forKey: .availableTime) ?? ""
        chargeType = c.merchantInteger(.chargeType)
        demand = try c.decodeIfPresent(String.self, forKey: .demand) ?? ""
        suitActivityTypes = try c.decodeIfPresent(String.self, forKey: .suitActivityTypes)
        coopOpen = c.merchantInteger(.coopOpen)
    }
    public var blocker: String? {
        let text = capacity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && (Int(text) == nil || Int(text)! < 0) { return "merchant.operations.capacityInvalid" }
        if let chargeType, ![0, 1].contains(chargeType) { return "merchant.operations.chargeUnknown" }
        return nil
    }
    public var fields: [String: Any] {
        var fields: [String: Any] = ["availableTime": availableTime.trimmingCharacters(in: .whitespacesAndNewlines), "demand": demand.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let capacity = Int(capacity.trimmingCharacters(in: .whitespacesAndNewlines)) { fields["capacity"] = capacity }
        if let chargeType { fields["chargeType"] = chargeType }
        if let suitActivityTypes { fields["suitActivityTypes"] = suitActivityTypes }
        if let coopOpen { fields["coopOpen"] = coopOpen }
        return fields
    }
}
public struct MerchantStorefront: Decodable, Equatable {
    public var profile: MerchantStoreProfile
    public var decor: MerchantStoreDecor
    public var cooperation: MerchantCoopSettings
    public init(from decoder: Decoder) throws {
        profile = try .init(from: decoder); decor = try .init(from: decoder); cooperation = try .init(from: decoder)
    }
}

public struct MerchantStoreCharacter: Decodable, Equatable {
    public var name = ""
    public var avatar = ""
    public var greeting = ""
    public var persona = ""
    public var knowledge = ""
    public let auditStatus: Int?
    public let enabled: Int?
    public let auditReason: String?
    public init() { auditStatus = nil; enabled = nil; auditReason = nil }
    private enum CodingKeys: String, CodingKey { case name, avatar, greeting, persona, knowledge, auditStatus, enabled, auditReason }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        greeting = try c.decodeIfPresent(String.self, forKey: .greeting) ?? ""
        persona = try c.decodeIfPresent(String.self, forKey: .persona) ?? ""
        knowledge = try c.decodeIfPresent(String.self, forKey: .knowledge) ?? ""
        auditStatus = c.merchantInteger(.auditStatus); enabled = c.merchantInteger(.enabled)
        auditReason = try c.decodeIfPresent(String.self, forKey: .auditReason)
    }
    public var reviewKey: String { MerchantOperationsReview.key(auditStatus) }
    public var blocker: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.operations.characterNameRequired" }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 32 { return "merchantPreset.nameLimit" }
        if avatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.operations.characterAvatarRequired" }
        if greeting.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 60 { return "merchant.operations.greetingLimit" }
        if persona.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 { return "merchantPreset.personaLimit" }
        if knowledge.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 2000 { return "merchant.operations.knowledgeLimit" }
        return nil
    }
    /// These five fields are the complete legacy self-service write contract. Explicit
    /// empty persona/knowledge strings clear the field; null would mean leave unchanged.
    /// Audit fields are read-only and never accompany npc/save.
    public var fields: [String: Any] {
        ["name": name, "avatar": avatar, "greeting": greeting, "persona": persona, "knowledge": knowledge]
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    public var rejectionReason: String? {
        guard auditStatus == 2, let reason = auditReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else { return nil }
        return reason
    }
}
public enum MerchantOperationsReview {
    public static func key(_ raw: Int?) -> String {
        switch raw { case 0: return "merchant.operations.review.pending"; case 1: return "merchant.operations.review.approved"
        case 2: return "merchant.operations.review.rejected"; default: return "merchant.operations.review.unknown" }
    }
}
public enum MerchantTemplateMethod: Int, CaseIterable {
    case secretWord = 1, photo, quiz, posterCode, gps
    public var titleKey: String { "merchant.operations.method.\(rawValue)" }
}
public struct MerchantNodeTemplate: Decodable, Equatable {
    public var id: Int?
    public var title = ""
    public var description = ""
    public var imgURL: String?
    public var method: MerchantTemplateMethod?
    public var questionAnswer = ""
    public var questionName = ""
    public var optionA = ""
    public var optionB = ""
    public var optionC = ""
    public var optionD = ""
    public var correctAnswer = ""
    public var feedbackText = ""
    public var couponID: Int?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case id, title, description, imgUrl, validationMethod, questionAnswer, questionName, questionA, questionB, questionC, questionD, correctAnswer, feedbackText, couponId
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.merchantInteger(.id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        imgURL = try c.decodeIfPresent(String.self, forKey: .imgUrl)
        method = c.merchantInteger(.validationMethod).flatMap(MerchantTemplateMethod.init(rawValue:))
        questionAnswer = try c.decodeIfPresent(String.self, forKey: .questionAnswer) ?? ""
        questionName = try c.decodeIfPresent(String.self, forKey: .questionName) ?? ""
        optionA = try c.decodeIfPresent(String.self, forKey: .questionA) ?? ""
        optionB = try c.decodeIfPresent(String.self, forKey: .questionB) ?? ""
        optionC = try c.decodeIfPresent(String.self, forKey: .questionC) ?? ""
        optionD = try c.decodeIfPresent(String.self, forKey: .questionD) ?? ""
        correctAnswer = try c.decodeIfPresent(String.self, forKey: .correctAnswer) ?? ""
        feedbackText = try c.decodeIfPresent(String.self, forKey: .feedbackText) ?? ""
        couponID = c.merchantInteger(.couponId)
    }
    public var blocker: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.operations.titleRequired" }
        guard let method else { return "merchant.operations.methodRequired" }
        if method == .secretWord && questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.operations.answerRequired" }
        if method == .quiz {
            if questionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.operations.questionRequired" }
            let options = [optionA, optionB, optionC, optionD].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if options.filter({ !$0.isEmpty }).count < 2 { return "merchant.operations.optionsRequired" }
            let key = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let index = ["A", "B", "C", "D"].firstIndex(of: key), !options[index].isEmpty else { return "merchant.operations.correctRequired" }
        }
        return nil
    }
    public var fields: [String: Any] {
        var fields: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let id { fields["id"] = id }; if let method { fields["validationMethod"] = method.rawValue }
        if let imgURL { fields["imgUrl"] = imgURL }; if let couponID { fields["couponId"] = couponID }
        for (key, value) in ["description": description, "questionAnswer": questionAnswer, "questionName": questionName,
                              "questionA": optionA, "questionB": optionB, "questionC": optionC, "questionD": optionD,
                              "correctAnswer": correctAnswer, "feedbackText": feedbackText] {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { fields[key] = text }
        }
        return fields
    }
}

public struct MerchantCityNodeRecord: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let address: String?
    public let status: Int?
    public let templateTitle: String?
    public let tagsText: String?
    public let validationMethod: Int?
    private enum CodingKeys: String, CodingKey { case poiId, id, name, address, status, templateTitle, tagsText, tags, validationMethod }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.poiId) ?? c.merchantInteger(.id), id > 0 else { throw APIError.malformedResponse }
        self.id = id; name = try c.decodeIfPresent(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address); status = c.merchantInteger(.status)
        templateTitle = try c.decodeIfPresent(String.self, forKey: .templateTitle)
        tagsText = try c.decodeIfPresent(String.self, forKey: .tagsText) ?? c.decodeIfPresent(String.self, forKey: .tags)
        validationMethod = c.merchantInteger(.validationMethod)
    }
}
public struct MerchantCityApplication: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let status: Int?
    public let reason: String?
    public let applicationType: Int?
    public var reviewKey: String { MerchantOperationsReview.key(status) }
    private enum CodingKeys: String, CodingKey { case id, poiName, name, auditStatus, status, auditReason, rejectReason, applicationType }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0 else { throw APIError.malformedResponse }
        self.id = id; name = try c.decodeIfPresent(String.self, forKey: .poiName) ?? c.decodeIfPresent(String.self, forKey: .name)
        status = c.merchantInteger(.auditStatus) ?? c.merchantInteger(.status)
        reason = try c.decodeIfPresent(String.self, forKey: .auditReason) ?? c.decodeIfPresent(String.self, forKey: .rejectReason)
        applicationType = c.merchantInteger(.applicationType)
    }
}
public struct MerchantCityCatalog: Decodable, Equatable {
    public let nodes: [MerchantCityNodeRecord]
    public let applications: [MerchantCityApplication]
    public let used: Int?
    public let max: Int?
    public var quotaExhausted: Bool { if let used, let max, max > 0 { return used >= max }; return false }
    private enum CodingKeys: String, CodingKey { case nodes, applications, used, max }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try c.decode([MerchantCityNodeRecord].self, forKey: .nodes)
        applications = try c.decode([MerchantCityApplication].self, forKey: .applications)
        used = c.merchantInteger(.used); max = c.merchantInteger(.max)
        guard Set(nodes.map(\.id)).count == nodes.count, Set(applications.map(\.id)).count == applications.count else { throw APIError.malformedResponse }
    }
}
public struct MerchantTemplateRecord: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let description: String?
    public let imgUrl: String?
    public let validationMethod: Int?
    public let status: Int?
    public let publishStatus: Int?
}
public struct MerchantVoiceResource: Decodable, Equatable {
    public let voiceStatus: Int?
    public let voiceSample: String?
    public var statusKey: String {
        switch voiceStatus { case 0: return "merchant.operations.voice.unset"; case 1: return "merchant.operations.voice.generating"
        case 2: return "merchant.operations.voice.ready"; case 3: return "merchant.operations.voice.failed"
        default: return "merchant.operations.review.unknown" }
    }
}
public struct MerchantAvatarResource: Decodable, Equatable {
    public let available: Bool
    public let styles: [String]
    public let job: Job?
    public struct Job: Decodable, Equatable {
        public let jobId: Int
        public let status: String
        public let style: String?
        public let modelUrl: String?
        public let thumbUrl: String?
        public let failReason: String?
        public var statusKey: String {
            switch status { case "PENDING": return "merchant.operations.avatar.pending"; case "SUCCEEDED": return "merchant.operations.avatar.ready"
            case "FAILED": return "merchant.operations.avatar.failed"; default: return "merchant.operations.review.unknown" }
        }
    }
}
public struct MerchantAssetResources: Equatable {
    public let voice: MerchantVoiceResource
    public let avatar: MerchantAvatarResource
    public init(voice: MerchantVoiceResource, avatar: MerchantAvatarResource) { self.voice = voice; self.avatar = avatar }
}

/// Exact display-only business-status contract. Unknown values fail closed.
public enum MerchantBusinessStatus: Int, Decodable, Equatable, CaseIterable {
    case closed = 0, open = 1
    public var titleKey: String { self == .open ? "merchant.operations.statusOpen" : "merchant.operations.statusClosed" }
}
public struct MerchantBusinessStatusDocument: Decodable, Equatable {
    public let businessStatus: MerchantBusinessStatus
}

/// The server derives ownership from access/me; this local owner fence is never transmitted.
public struct MerchantStoreBusinessStatus: Equatable {
    public let merchantID: Int
    public var status: MerchantBusinessStatus
    public init(merchantID: Int, status: MerchantBusinessStatus) throws {
        guard merchantID > 0 else { throw APIError.invalidRequest }
        self.merchantID = merchantID; self.status = status
    }
}

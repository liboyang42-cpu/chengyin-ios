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
        if (coverImage ?? "").isEmpty && slogan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cityRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && storyTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && gallery.isEmpty && tags.isEmpty && (categoryID ?? 0) <= 0 && !(featuredType == 0 && featuredID == nil) { return "merchant.operations.decorEmpty" }
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
    private var loadedCapacity: String
    /// A missing or already-empty source value is never an implicit clear request.
    public var clearsCapacity: Bool {
        !loadedCapacity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && capacity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Baseline freshness compares returned form facts, not local edit bookkeeping.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.capacity == rhs.capacity && lhs.availableTime == rhs.availableTime && lhs.chargeType == rhs.chargeType
            && lhs.demand == rhs.demand && lhs.suitActivityTypes == rhs.suitActivityTypes && lhs.coopOpen == rhs.coopOpen
    }
    /// Only a definite acknowledgement consumes this local edit intent.
    mutating func acknowledgeCapacityEdit() {
        if clearsCapacity { capacity = "" }
        loadedCapacity = capacity
    }
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
        loadedCapacity = capacity
        availableTime = try c.decodeIfPresent(String.self, forKey: .availableTime) ?? ""
        chargeType = c.merchantInteger(.chargeType)
        demand = try c.decodeIfPresent(String.self, forKey: .demand) ?? ""
        suitActivityTypes = try c.decodeIfPresent(String.self, forKey: .suitActivityTypes)
        coopOpen = c.merchantInteger(.coopOpen)
    }
    public var blocker: String? {
        let text = capacity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && (Int(text) == nil || Int(text)! < 0) { return "merchant.operations.capacityInvalid" }
        guard let chargeType else { return "merchant.coopChargeChoice.required" }
        if ![0, 1].contains(chargeType) { return "merchant.operations.chargeUnknown" }
        return nil
    }
    public var fields: [String: Any] {
        var fields: [String: Any] = ["availableTime": availableTime.trimmingCharacters(in: .whitespacesAndNewlines), "demand": demand.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let capacity = Int(capacity.trimmingCharacters(in: .whitespacesAndNewlines)) { fields["capacity"] = capacity }
        else if clearsCapacity { fields["capacity"] = NSNull(); fields["params"] = ["clearCapacity": true] }
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
/// Exact Mini VENUE_OPTIONS. These are template descriptions, not location grants.
public enum MerchantTemplateVenueChoice: String, CaseIterable {
    case scenicArea = "景区", park = "公园绿地", shoppingDistrict = "商圈街区"
    case historicDistrict = "古镇老街", museum = "博物馆", campus = "校园", indoorVenue = "室内场馆"
    public var titleKey: String {
        switch self {
        case .scenicArea: return "merchant.preparation.venue.scenicArea"
        case .park: return "merchant.preparation.venue.park"
        case .shoppingDistrict: return "merchant.preparation.venue.shoppingDistrict"
        case .historicDistrict: return "merchant.preparation.venue.historicDistrict"
        case .museum: return "merchant.preparation.venue.museum"
        case .campus: return "merchant.preparation.venue.campus"
        case .indoorVenue: return "merchant.preparation.venue.indoorVenue"
        }
    }
}

public enum MerchantTemplateMethod: Int, CaseIterable {
    case secretWord = 1, photo, quiz, posterCode, gps
    public var titleKey: String { "merchant.operations.method.\(rawValue)" }
}
/// Merchant-confirmed planning facts for this editing session only. The current native
/// save contract has no mapping for this group; never enter it in AI or API payloads.
public struct MerchantTemplateParticipationPlan: Equatable {
    public enum Staffing: String, CaseIterable {
        case unspecified, selfGuided, staffRequired
        public var titleKey: String { "merchant.participation.staffing." + rawValue }
    }
    public var durationMinutes = ""
    public var maximumParticipants = ""
    public var staffing: Staffing = .unspecified
    public init() {}
    public var blocker: String? {
        if Self.positiveInteger(durationMinutes) == nil { return "merchant.participation.durationInvalid" }
        if Self.positiveInteger(maximumParticipants) == nil { return "merchant.participation.capacityInvalid" }
        if staffing == .unspecified { return "merchant.participation.staffingRequired" }
        return nil
    }
    /// Accept only whole, positive decimal counts, never signs, fractions or exponents.
    public static func positiveInteger(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let number = Int(value), number > 0 else { return nil }
        return number
    }
}

/// Manually authored contingencies for this editing session, not approved runtime
/// branches. No server decode or write mapping is inferred from these local fields.
public struct MerchantTemplateExitPlan: Equatable {
    public static let maximumTextLength = 600
    public var offlineAlternative = ""
    public var failureExit = ""
    public init() {}
    public var blocker: String? {
        if offlineAlternative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.exitPlan.offlineRequired" }
        if offlineAlternative.utf16.count > Self.maximumTextLength { return "merchant.exitPlan.textLimit" }
        if failureExit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "merchant.exitPlan.exitRequired" }
        if failureExit.utf16.count > Self.maximumTextLength { return "merchant.exitPlan.textLimit" }
        return nil
    }
}

/// Mini's ruleInstructions editor: one player-facing instruction per line.
/// These are editor limits, not a claim that every legacy server value follows them.
public struct MerchantTemplateRuleSteps: Equatable {
    public static let maximumSteps = 12
    public static let maximumStepLength = 60
    private let sourceText: String?
    public private(set) var rows: [String]
    public private(set) var isEdited = false
    public init(sourceText: String? = nil) {
        self.sourceText = sourceText
        let lines = (sourceText ?? "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        rows = lines.isEmpty ? [""] : lines
    }
    /// Missing/null stays omitted; merely opening an old template never rewrites its text.
    /// An explicit all-empty edit is an empty String, supported by the existing != null SQL.
    public var wireValue: String? {
        guard isEdited else { return sourceText }
        return rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    public var isClearing: Bool {
        isEdited && wireValue == "" && !(sourceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var canAdd: Bool { rows.count < Self.maximumSteps }
    public mutating func update(at index: Int, text: String) {
        guard rows.indices.contains(index), rows[index] != text else { return }
        rows[index] = text; isEdited = true
    }
    public mutating func add() {
        guard canAdd else { return }
        rows.append(""); isEdited = true
    }
    public mutating func remove(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index); isEdited = true
    }
    public var blocker: String? {
        guard isEdited else { return nil }
        if rows.count > Self.maximumSteps { return "merchant.ruleSteps.countLimit" }
        if rows.contains(where: { $0.rangeOfCharacter(from: .newlines) != nil }) { return "merchant.ruleSteps.oneLine" }
        if rows.contains(where: { $0.utf16.count > Self.maximumStepLength }) { return "merchant.ruleSteps.textLimit" }
        return nil
    }
}

/// Existing Mini hint group. The enabled switch is editor state, never a backend flag.
public struct MerchantTemplateHints: Equatable {
    public enum Field: String, CaseIterable, Identifiable {
        case hint1, hint2, answerReveal
        public var id: String { rawValue }
        public var titleKey: String { "merchant.hints." + rawValue }
    }
    private let sourceFields: [String: String]
    private let sourceMethod: MerchantTemplateMethod?
    private var values: [Field: String]
    public private(set) var enabled: Bool
    public private(set) var isEdited = false
    public init(hint1: String? = nil, hint2: String? = nil, answerReveal: String? = nil,
                method: MerchantTemplateMethod? = nil) {
        sourceFields = ["hint1": hint1, "hint2": hint2, "answerReveal": answerReveal].compactMapValues { $0 }
        // An absent/empty group has no method-dependent source state. Keep legacy
        // no-hint templates equivalent to a freshly constructed empty group.
        sourceMethod = sourceFields.values.contains { !$0.isEmpty } ? method : nil
        values = [.hint1: hint1 ?? "", .hint2: hint2 ?? "", .answerReveal: answerReveal ?? ""]
        enabled = sourceFields.values.contains { !$0.isEmpty }
    }
    public static func supports(_ method: MerchantTemplateMethod?) -> Bool {
        method == .secretWord || method == .quiz || method == .gps
    }
    public func text(_ field: Field) -> String { values[field] ?? "" }
    public mutating func update(_ field: Field, text: String) {
        guard enabled, values[field] != text else { return }
        values[field] = text; isEdited = true
    }
    public mutating func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; isEdited = true
        if !value { for field in Field.allCases { values[field] = "" } }
    }
    /// The exact String fields support empty updates. Missing source values stay omitted
    /// until this group is explicitly edited; no unrelated edit silently clears hints.
    public var fields: [String: String] {
        guard isEdited else { return sourceFields }
        return Dictionary(uniqueKeysWithValues: Field.allCases.map { ($0.rawValue, enabled ? text($0) : "") })
    }
    public var clearedFields: [Field] {
        guard isEdited else { return [] }
        return Field.allCases.filter { !(sourceFields[$0.rawValue] ?? "").isEmpty && fields[$0.rawValue] == "" }
    }
    public var previewStages: [Field] {
        guard enabled else { return [] }
        return Field.allCases.filter { !text($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    public func blocker(method: MerchantTemplateMethod?) -> String? {
        // Grandfather untouched legacy content. Changing to an unsupported completion
        // method must not silently erase it as a hidden side effect.
        enabled && !Self.supports(method) && (isEdited || method != sourceMethod)
            ? "merchant.hints.methodConflict" : nil
    }
}

/// The existing storyJson timeline, kept separate from the store's own story editor.
/// Unknown source shapes remain opaque: no fallback may silently replace richer content.
public struct MerchantTemplateStoryTimeline: Equatable {
    public struct Beat: Equatable, Identifiable {
        public let id: Int
        public fileprivate(set) var text: String
        public fileprivate(set) var tag: String
        private let sourceImages: [String]?
        private let legacyImage: String?
        public var images: [String] { sourceImages ?? legacyImage.map { $0.isEmpty ? [] : [$0] } ?? [] }
        public var imageReferenceCount: Int { (sourceImages?.count ?? 0) + ((legacyImage ?? "").isEmpty ? 0 : 1) }
        fileprivate init(id: Int, text: String = "", tag: String = "", images: [String]? = [], legacyImage: String? = nil) {
            self.id = id; self.text = text; self.tag = tag; sourceImages = images; self.legacyImage = legacyImage
        }
        fileprivate var object: [String: Any] {
            var result: [String: Any] = ["text": text, "tag": tag]
            if let sourceImages { result["imgs"] = sourceImages }
            if let legacyImage { result["img"] = legacyImage }
            if sourceImages == nil && legacyImage == nil { result["imgs"] = [String]() }
            return result
        }
        fileprivate var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageReferenceCount > 0 }
    }
    private let sourceText: String?
    private let sourceJSON: String?
    private let sourceImageCount: Int
    private let sourceBeats: [Beat]
    private var nextID: Int
    public let isEditable: Bool
    public private(set) var beats: [Beat]
    public private(set) var enabled: Bool
    public private(set) var isEdited = false
    public init(storyText: String? = nil, storyJSON: String? = nil) {
        sourceText = storyText; sourceJSON = storyJSON
        if let raw = storyJSON, !raw.isEmpty {
            if let parsed = Self.parse(raw) {
                beats = parsed.isEmpty ? [Beat(id: 1, text: storyText ?? "")] : parsed
                isEditable = true; enabled = !parsed.isEmpty || !(storyText ?? "").isEmpty
            } else {
                beats = []; isEditable = false; enabled = true
            }
        } else {
            beats = [Beat(id: 1, text: storyText ?? "")]; isEditable = true
            enabled = !(storyText ?? "").isEmpty
        }
        sourceBeats = beats
        sourceImageCount = beats.reduce(0) { $0 + $1.imageReferenceCount }
        nextID = beats.count + 1
    }
    private static func parse(_ raw: String) -> [Beat]? {
        guard let array = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] else { return nil }
        var result: [Beat] = []
        for (index, item) in array.enumerated() {
            guard Set(item.keys).isSubset(of: ["text", "tag", "imgs", "img"]) else { return nil }
            for key in ["text", "tag", "img"] {
                if let value = item[key], !(value is NSNull), !(value is String) { return nil }
            }
            var images: [String]?
            if let value = item["imgs"], !(value is NSNull) {
                guard let strings = value as? [String] else { return nil }; images = strings
            }
            result.append(Beat(id: index + 1, text: (item["text"] as? String) ?? "", tag: (item["tag"] as? String) ?? "",
                               images: images, legacyImage: item["img"] as? String))
        }
        return result
    }
    public mutating func setEnabled(_ value: Bool) {
        guard isEditable, value != enabled else { return }
        enabled = value; isEdited = true
        if !value { beats = [Beat(id: nextID)]; nextID += 1 }
    }
    public mutating func update(_ id: Int, text: String? = nil, tag: String? = nil) {
        guard isEditable, enabled, let index = beats.firstIndex(where: { $0.id == id }) else { return }
        let before = beats[index]
        if let text { beats[index].text = text }; if let tag { beats[index].tag = tag }
        if beats[index] != before { isEdited = true }
    }
    public mutating func add() {
        guard isEditable, enabled else { return }
        beats.append(Beat(id: nextID)); nextID += 1; isEdited = true
    }
    public mutating func remove(_ id: Int) {
        guard isEditable, enabled, beats.count > 1, let index = beats.firstIndex(where: { $0.id == id }) else { return }
        beats.remove(at: index); isEdited = true
    }
    public mutating func move(_ id: Int, offset: Int) {
        guard isEditable, enabled, [-1, 1].contains(offset), let index = beats.firstIndex(where: { $0.id == id }),
              beats.indices.contains(index + offset) else { return }
        beats.swapAt(index, index + offset); isEdited = true
    }
    public var previewBeats: [Beat] { enabled ? beats.filter(\.hasContent) : [] }
    private var fullProjection: String { previewBeats.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n") }
    /// Mini's existing <=500 UTF-16-unit summary; full text remains in storyJson.
    /// Keep a whole Swift Character at the boundary rather than splitting a surrogate.
    public var textProjection: String {
        var result = "", count = 0
        for character in fullProjection {
            let length = String(character).utf16.count
            guard count + length <= 500 else { break }
            result.append(character); count += length
        }
        return result
    }
    public var projectionIsShortened: Bool { isEdited && enabled && textProjection != fullProjection }
    private var editedJSON: String? {
        guard enabled, !previewBeats.isEmpty else { return "" }
        guard let data = try? JSONSerialization.data(withJSONObject: previewBeats.map(\.object), options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public var fields: [String: String] {
        guard isEdited else { return ["storyText": sourceText, "storyJson": sourceJSON].compactMapValues { $0 } }
        guard let json = editedJSON else { return [:] }
        return ["storyText": enabled ? textProjection : "", "storyJson": json]
    }
    public var removedImageCount: Int { isEdited ? max(0, sourceImageCount - previewBeats.reduce(0) { $0 + $1.imageReferenceCount }) : 0 }
    public var removedBeats: [Beat] {
        guard isEdited else { return [] }
        let retained = Set(previewBeats.map(\.id))
        return sourceBeats.filter { $0.hasContent && !retained.contains($0.id) }
    }
    public var clearsSource: Bool {
        isEdited && fields["storyJson"] == "" && (!(sourceText ?? "").isEmpty || !(sourceJSON ?? "").isEmpty)
    }
    public var blocker: String? {
        guard isEdited else { return nil }
        guard isEditable else { return "merchant.storyTimeline.opaque" }
        if enabled && beats.contains(where: { !$0.hasContent && !$0.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "merchant.storyTimeline.tagNeedsContent"
        }
        return editedJSON == nil ? "merchant.storyTimeline.encodingFailed" : nil
    }
}

public struct MerchantNodeTemplate: Decodable, Equatable {
    public var id: Int?
    public var title = ""
    public var description = ""
    /// Existing server metadata: duration is minutes; players is descriptive game player-count text,
    /// never the venue's maximumParticipants or an approved capacity constraint.
    public var gameDurationMinutes = ""
    public var players = ""
    /// Existing persisted preparation fields; unfamiliar source venue values are preserved.
    public var usageLocation = ""
    public var requiredMaterials = ""
    public var ruleSteps = MerchantTemplateRuleSteps()
    public var hints = MerchantTemplateHints()
    public var storyTimeline = MerchantTemplateStoryTimeline()
    public var categories = MerchantTemplateCategories()
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
    /// Nil preserves legacy drafts. Adding a plan explicitly opts into local-only review.
    public var participationPlan: MerchantTemplateParticipationPlan?
    /// Explicit, independent opt-in; held only until this edit session ends.
    public var exitPlan: MerchantTemplateExitPlan?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case id, title, description, duration, players, imgUrl, validationMethod, questionAnswer, questionName, questionA, questionB, questionC, questionD, correctAnswer, feedbackText, couponId, usageLocation, requiredMaterials, ruleInstructions, hint1, hint2, answerReveal, storyText, storyJson, categoryId, activityCategoryids, sysCategoryList
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.merchantInteger(.id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        if c.contains(.duration), try !c.decodeNil(forKey: .duration) {
            if let number = try? c.decode(Int.self, forKey: .duration) { gameDurationMinutes = String(number) }
            else { gameDurationMinutes = try c.decode(String.self, forKey: .duration) }
            guard Self.validDuration(gameDurationMinutes) != nil else { throw APIError.malformedResponse }
        }
        players = try c.decodeIfPresent(String.self, forKey: .players) ?? ""
        usageLocation = try c.decodeIfPresent(String.self, forKey: .usageLocation) ?? ""
        requiredMaterials = try c.decodeIfPresent(String.self, forKey: .requiredMaterials) ?? ""
        ruleSteps = .init(sourceText: try c.decodeIfPresent(String.self, forKey: .ruleInstructions))
        imgURL = try c.decodeIfPresent(String.self, forKey: .imgUrl)
        method = c.merchantInteger(.validationMethod).flatMap(MerchantTemplateMethod.init(rawValue:))
        hints = .init(hint1: try c.decodeIfPresent(String.self, forKey: .hint1),
                      hint2: try c.decodeIfPresent(String.self, forKey: .hint2),
                      answerReveal: try c.decodeIfPresent(String.self, forKey: .answerReveal), method: method)
        storyTimeline = .init(storyText: try c.decodeIfPresent(String.self, forKey: .storyText),
                              storyJSON: try c.decodeIfPresent(String.self, forKey: .storyJson))
        let primaryCategory: Int?
        if !c.contains(.categoryId) { primaryCategory = nil }
        else if try c.decodeNil(forKey: .categoryId) { primaryCategory = nil }
        else if let value = try? c.decode(Int.self, forKey: .categoryId) { primaryCategory = value }
        else {
            let raw = try c.decode(String.self, forKey: .categoryId)
            guard let value = Int(raw) else { throw APIError.malformedResponse }; primaryCategory = value
        }
        categories = .init(rawIDs: try c.decodeIfPresent(String.self, forKey: .activityCategoryids), primaryID: primaryCategory,
                           labels: try c.decodeIfPresent([MerchantTemplateCategory].self, forKey: .sysCategoryList) ?? [])
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
        if !gameDurationMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.validDuration(gameDurationMinutes) == nil { return "merchant.templateMetadata.durationInvalid" }
        if let blocker = ruleSteps.blocker { return blocker }
        if let blocker = hints.blocker(method: method) { return blocker }
        if let blocker = storyTimeline.blocker { return blocker }
        return participationPlan?.blocker ?? exitPlan?.blocker
    }
    /// Backend entity Long is copied through an Integer DTO with Math.toIntExact.
    /// Zero is the existing server's creation default; missing remains omitted.
    public static func validDuration(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let number = Int(value), number >= 0, number <= Int(Int32.max) else { return nil }
        return number
    }
    /// Exact legacy wire fields only. A local participation plan is not a server fact.
    public var fields: [String: Any] {
        var fields: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let id { fields["id"] = id }; if let method { fields["validationMethod"] = method.rawValue }
        if let duration = Self.validDuration(gameDurationMinutes) { fields["duration"] = duration }
        // Picker choices are exact wire values; preserve unfamiliar loaded values byte-for-byte.
        if !usageLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["usageLocation"] = usageLocation }
        if let rules = ruleSteps.wireValue { fields["ruleInstructions"] = rules }
        for (key, value) in hints.fields { fields[key] = value }
        for (key, value) in storyTimeline.fields { fields[key] = value }
        for (key, value) in categories.fields { fields[key] = value }
        if let imgURL { fields["imgUrl"] = imgURL }; if let couponID { fields["couponId"] = couponID }
        for (key, value) in ["description": description, "players": players, "requiredMaterials": requiredMaterials, "questionAnswer": questionAnswer, "questionName": questionName,
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

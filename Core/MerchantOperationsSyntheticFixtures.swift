#if DEBUG
import Foundation

/// Synthetic records only; no URLSession, provider SDK, permission prompt or disk write.
@MainActor public final class MerchantOperationsFixtureReader: MerchantOperationsReading {
    public private(set) var scope = UUID()
    public var isConfigured = true
    public var isAuthenticated = true
    public var isOfflineExample: Bool { true }
    public var denied = false
    public var failure: APIError?
    public var saveFailure: MerchantOperationsFailure?
    public private(set) var saveCount = 0
    public private(set) var accessCount = 0
    public private(set) var documents: [MerchantOperationsDestination: MerchantOperationsDocument] = [:]
    public init() {
        do {
            let store = try JSONDecoder().decode(MerchantStorefront.self, from: Data(MerchantOperationsFixtureData.storeJSON.utf8))
            let character = try JSONDecoder().decode(MerchantStoreCharacter.self, from: Data(MerchantOperationsFixtureData.characterJSON.utf8))
            let template = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(MerchantOperationsFixtureData.templateJSON.utf8))
            documents[.businessStatus] = .draft(.businessStatus(try .init(merchantID: 31, status: .open)))
            documents[.profile] = .draft(.profile(store.profile)); documents[.decor] = .draft(.decor(store.decor))
            documents[.gallery] = .draft(.gallery(store.decor)); documents[.story] = .draft(.story(store))
            documents[.cooperation] = .draft(.cooperation(store.cooperation)); documents[.character] = .draft(.character(character))
            documents[.template(71)] = .draft(.template(template)); documents[.template(nil)] = .draft(.template(.init()))
            var unknownTemplate = template; unknownTemplate.id = 72; unknownTemplate.title = "Unknown source status"; unknownTemplate.method = nil
            documents[.template(72)] = .draft(.template(unknownTemplate))
            documents[.cityNodes] = .cityNodes(try JSONDecoder().decode(MerchantCityCatalog.self, from: Data(MerchantOperationsFixtureData.cityJSON.utf8)))
            documents[.templates] = .templates(try JSONDecoder().decode([MerchantTemplateRecord].self, from: Data(MerchantOperationsFixtureData.templatesJSON.utf8)))
            let voice = try JSONDecoder().decode(MerchantVoiceResource.self, from: Data(#"{"voiceStatus":1,"voiceSample":null}"#.utf8))
            let avatar = try JSONDecoder().decode(MerchantAvatarResource.self, from: Data(#"{"available":false,"styles":[],"job":{"jobId":41,"status":"FAILED","style":"illustrated","modelUrl":null,"thumbUrl":null,"failReason":"Synthetic provider unavailable"}}"#.utf8))
            documents[.assets] = .assets(.init(voice: voice, avatar: avatar))
        } catch { failure = .malformedResponse }
    }
    public func access() async throws -> MerchantOperationsAccess {
        accessCount += 1
        guard isAuthenticated else { throw APIError.unauthorized }
        if let failure { throw failure }
        let permissions = denied ? [] : ["merchant:basic:read", "merchant:profile:write", "merchant:coop:manage", "merchant:project:manage"]
        let data = try JSONSerialization.data(withJSONObject: ["active": !denied, "merchant": ["id": 31, "name": "Synthetic Lantern Store"], "roleCode": "MERCHANT_OWNER", "permissions": permissions])
        return try JSONDecoder().decode(MerchantOperationsAccess.self, from: data)
    }
    public func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        guard try await access().allows(destination) else { throw MerchantOperationsFailure.accessDenied }
        guard let document = documents[destination] else { throw APIError.malformedResponse }
        return document
    }
    public func saveExample(_ draft: MerchantOperationsDraft) async throws {
        guard try await access().allows(draft.destination) else { throw MerchantOperationsFailure.accessDenied }
        guard draft.blocker == nil else { throw MerchantOperationsFailure.notSent }
        saveCount += 1
        if let saveFailure { throw saveFailure }
        if case .profile(let profile) = draft, let hours = profile.businessTimeReplacement {
            var fields = profile.fields
            fields["id"] = profile.id; fields["businessTime"] = hours
            let returned = try JSONDecoder().decode(MerchantStoreProfile.self, from: JSONSerialization.data(withJSONObject: fields))
            documents[.profile] = .draft(.profile(returned))
        } else { documents[draft.destination] = .draft(draft) }
    }
    public func replace(_ destination: MerchantOperationsDestination, with document: MerchantOperationsDocument) { documents[destination] = document }
    public func signOut() { isAuthenticated = false; scope = UUID() }
    public func switchAccount() { scope = UUID(); isAuthenticated = false }
}
public enum MerchantOperationsFixtureData {
    public static let storeJSON = #"{"id":31,"name":"Synthetic Lantern Store","logo":"","description":"A synthetic local shop story.","derivatives":"Postcards","website":"","preference":"Quiet visits","coverImage":"","slogan":"Find a little wonder","cityRole":"Neighborhood meeting place","storyTitle":"Preserved hidden story title","gallery":"[\"synthetic-gallery-1\",\"synthetic-gallery-2\"]","tags":"Quiet;Evening","categoryId":8,"featuredType":2,"featuredId":17,"serviceTag":"Host","serviceText":"Preserved service text","locationLat":31.2,"locationLng":121.4,"locationVerified":1,"capacity":12,"availableTime":"Weekends","chargeType":0,"demand":"Small creative gatherings","suitActivityTypes":"walk;workshop","coopOpen":1}"#
    public static let characterJSON = #"{"id":12,"name":"Lantern","avatar":"synthetic-character-avatar","greeting":"Welcome to the example store","persona":"A friendly fictional guide","knowledge":"Synthetic neighborhood stories only","auditStatus":2,"enabled":0}"#
    public static let templateJSON = #"{"id":71,"title":"Lantern riddle","description":"Synthetic owner-only template","validationMethod":3,"questionName":"Which sign is by the door?","questionA":"A lantern","questionB":"A clock","correctAnswer":"A","feedbackText":"Thanks for exploring","couponId":19}"#
    public static let templatesJSON = #"[{"id":71,"title":"Lantern riddle","description":"Synthetic owner-only template","imgUrl":null,"validationMethod":3,"status":2,"publishStatus":0},{"id":72,"title":"Unknown source status","description":null,"imgUrl":null,"validationMethod":9,"status":99,"publishStatus":null}]"#
    public static let cityJSON = #"{"nodes":[{"poiId":41,"name":"Synthetic courtyard","address":"Example address","status":1,"templateTitle":"Lantern riddle","tagsText":"Quiet","validationMethod":3}],"applications":[{"id":81,"poiName":"Synthetic riverside","auditStatus":2,"auditReason":"Synthetic location needs review","applicationType":2},{"id":82,"name":"Synthetic unknown status","status":99,"applicationType":1}],"used":1,"max":3}"#
}
#endif

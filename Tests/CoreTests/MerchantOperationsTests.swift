import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MerchantOperationsTransport: HTTPTransport {
    var replies: [String] = []
    var status = 200
    var failure: Error?
    var requests: [URLRequest] = []
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        if let failure { throw failure }
        return (Data((replies.isEmpty ? #"{"code":200,"data":{}}"# : replies.removeFirst()).utf8), status)
    }
}
final class MerchantOperationsContractTests: XCTestCase {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    func testInactiveAccessNeverInheritsWriteGrants() throws {
        let access = try decode(MerchantOperationsAccess.self, #"{"active":false,"permissions":["merchant:profile:write","merchant:coop:manage"]}"#)
        XCTAssertFalse(access.profileWrite); XCTAssertFalse(access.cooperationManage); XCTAssertFalse(access.allows(.character))
    }
    func testOwnerRoleAloneDoesNotGrantProfileOrCooperation() throws {
        let access = try decode(MerchantOperationsAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}"#)
        XCTAssertFalse(access.allows(.profile)); XCTAssertFalse(access.allows(.cooperation)); XCTAssertFalse(access.allows(.template(nil)))
        XCTAssertTrue(access.allows(.character)); XCTAssertTrue(access.allows(.cityNodes))
    }
    func testProfileOnlyEncodesSixWhitelistedFields() throws {
        let profile = try decode(MerchantStoreProfile.self, MerchantOperationsFixtureData.storeJSON)
        XCTAssertEqual(Set(profile.fields.keys), ["logo", "name", "description", "derivatives", "website", "preference"])
        XCTAssertNil(profile.fields["address"]); XCTAssertNil(profile.fields["locationLat"]); XCTAssertNil(profile.fields["id"])
    }
    func testDecorAcceptsJSONListAndLegacySemicolon() throws {
        let decor = try decode(MerchantStoreDecor.self, #"{"gallery":"[\"a;b\",\" c \" ]","tags":" calm ; ; evening "}"#)
        XCTAssertEqual(decor.gallery, ["a;b", "c"]); XCTAssertEqual(decor.tags, ["calm", "evening"])
    }
    func testDecorEmptyGalleryUsesCanonicalArrayString() throws {
        let decor = try decode(MerchantStoreDecor.self, #"{"gallery":[],"slogan":" Hello "}"#)
        let fields = try decor.fields()
        XCTAssertEqual(fields["gallery"] as? String, "[]"); XCTAssertEqual(fields["slogan"] as? String, "Hello")
    }
    func testGalleryPatchDoesNotOverwriteDecorFields() throws {
        var value = try decode(MerchantStoreDecor.self, MerchantOperationsFixtureData.storeJSON); value.gallery = []
        let request = try XCTUnwrap(MerchantOperationsDraft.gallery(value).previews().first)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.json) as? [String: Any])
        XCTAssertEqual(request.path, "api/merchant/decor/save"); XCTAssertEqual(Set(fields.keys), ["gallery"])
        XCTAssertEqual(fields["gallery"] as? String, "[]")
    }
    func testGalleryLimitAndFeaturedPairValidation() throws {
        var decor = try decode(MerchantStoreDecor.self, #"{"slogan":"hello","featuredType":2}"#)
        XCTAssertEqual(decor.blocker, "merchant.operations.featuredIncomplete")
        decor.featuredID = 8; XCTAssertNil(decor.blocker)
        decor.gallery = Array(repeating: "example", count: 10); XCTAssertEqual(decor.blocker, "merchant.operations.galleryLimit")
    }
    func testDecorPreservesHiddenFields() throws {
        var value = try decode(MerchantStoreDecor.self, MerchantOperationsFixtureData.storeJSON); value.slogan = "Edited"
        let fields = try value.fields()
        XCTAssertEqual(fields["categoryId"] as? Int, 8); XCTAssertEqual(fields["locationVerified"] as? Int, 1)
        XCTAssertEqual(fields["serviceText"] as? String, "Preserved service text")
        XCTAssertEqual(fields["featuredId"] as? Int, 17)
    }
    func testStoryKeepsHiddenTitleAndIsTwoOperationPreview() throws {
        var value = try decode(MerchantStorefront.self, MerchantOperationsFixtureData.storeJSON); value.profile.description = "New story"
        let previews = try MerchantOperationsDraft.story(value).previews()
        XCTAssertEqual(previews.map(\.path), ["api/merchant/decor/save", "api/merchant/update"])
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: previews[0].json) as? [String: String])
        XCTAssertEqual(fields, ["storyTitle": "Preserved hidden story title"])
    }
    func testStoryUsesSourceUTF16Limit() throws {
        var value = try decode(MerchantStorefront.self, MerchantOperationsFixtureData.storeJSON)
        value.profile.description = String(repeating: "a", count: 301)
        XCTAssertEqual(MerchantOperationsDraft.story(value).blocker, "merchant.operations.storyLimit")
    }
    func testCooperationPreservesBothHiddenOverwriteFields() throws {
        var value = try decode(MerchantCoopSettings.self, MerchantOperationsFixtureData.storeJSON); value.demand = "Edited"
        XCTAssertEqual(value.fields["suitActivityTypes"] as? String, "walk;workshop"); XCTAssertEqual(value.fields["coopOpen"] as? Int, 1)
        XCTAssertEqual(Set(value.fields.keys), ["capacity", "availableTime", "chargeType", "demand", "suitActivityTypes", "coopOpen"])
    }
    func testCooperationCapacityIsOptionalNonnegativeInteger() throws {
        var value = try decode(MerchantCoopSettings.self, #"{}"#)
        XCTAssertNil(value.blocker); XCTAssertNil(value.fields["capacity"])
        for text in ["-1", "1.5", "abc"] { value.capacity = text; XCTAssertEqual(value.blocker, "merchant.operations.capacityInvalid") }
        value.capacity = "0"; XCTAssertNil(value.blocker)
    }
    func testUnknownCooperationChargeIsNotFreeHosting() throws {
        let value = try decode(MerchantCoopSettings.self, #"{"chargeType":99}"#)
        XCTAssertEqual(value.chargeType, 99); XCTAssertEqual(value.blocker, "merchant.operations.chargeUnknown")
    }
    func testCharacterDoesNotTrustConfiguredConvenienceFields() throws {
        let value = try decode(MerchantStoreCharacter.self, #"{"configured":true,"statusText":"approved"}"#)
        XCTAssertEqual(value.reviewKey, "merchant.operations.review.unknown"); XCTAssertEqual(value.blocker, "merchant.operations.characterNameRequired")
    }
    func testCharacterValidationAndFiveFieldWhitelist() throws {
        var value = try decode(MerchantStoreCharacter.self, MerchantOperationsFixtureData.characterJSON)
        XCTAssertNil(value.blocker); XCTAssertEqual(Set(value.fields.keys), ["name", "avatar", "greeting", "persona", "knowledge"])
        value.greeting = String(repeating: "a", count: 61); XCTAssertEqual(value.blocker, "merchant.operations.greetingLimit")
        value.greeting = ""; value.avatar = ""; XCTAssertEqual(value.blocker, "merchant.operations.characterAvatarRequired")
    }
    func testTemplateNeverDefaultsVerificationMethod() throws {
        var value = MerchantNodeTemplate(); value.title = "Example"
        XCTAssertNil(value.method); XCTAssertEqual(value.blocker, "merchant.operations.methodRequired")
        value.method = .secretWord; XCTAssertEqual(value.blocker, "merchant.operations.answerRequired")
        value.questionAnswer = "hello"; XCTAssertNil(value.blocker)
    }
    func testQuizCorrectOptionMustContainContent() throws {
        var value = try decode(MerchantNodeTemplate.self, MerchantOperationsFixtureData.templateJSON)
        XCTAssertNil(value.blocker); value.correctAnswer = "C"; XCTAssertEqual(value.blocker, "merchant.operations.correctRequired")
        value.correctAnswer = "A"; value.optionB = ""; XCTAssertEqual(value.blocker, "merchant.operations.optionsRequired")
    }
    func testTemplateOmitsBlankOptionalFieldsAndPreservesCoupon() throws {
        var value = try decode(MerchantNodeTemplate.self, MerchantOperationsFixtureData.templateJSON); value.description = " "
        XCTAssertNil(value.fields["description"]); XCTAssertEqual(value.fields["couponId"] as? Int, 19)
        XCTAssertNil(value.fields["merchantId"]); XCTAssertNil(value.fields["ownerId"])
    }
    func testUnknownReviewRemainsUnknown() { for status in [nil, 3, 99, -1] as [Int?] { XCTAssertEqual(MerchantOperationsReview.key(status), "merchant.operations.review.unknown") } }
    func testCityNoQuotaDoesNotMeanZeroCapacity() throws {
        let value = try decode(MerchantCityCatalog.self, #"{"nodes":[],"applications":[],"used":0,"max":0}"#)
        XCTAssertFalse(value.quotaExhausted)
    }
    func testCityDuplicateAndInvalidIdentifiersAreMalformed() {
        XCTAssertThrowsError(try decode(MerchantCityCatalog.self, #"{"nodes":[{"id":1},{"id":1}],"applications":[]}"#))
        XCTAssertThrowsError(try decode(MerchantCityNodeRecord.self, #"{"poiId":0}"#))
    }
    func testCityApplicationUnknownStatusDoesNotBecomePending() throws {
        let value = try decode(MerchantCityApplication.self, #"{"id":8,"auditStatus":99,"status":1,"auditReason":"reason"}"#)
        XCTAssertEqual(value.status, 99); XCTAssertEqual(value.reviewKey, "merchant.operations.review.unknown")
    }
    func testResourcesUnknownStatusesAreNotReady() throws {
        let voice = try decode(MerchantVoiceResource.self, #"{"voiceStatus":91}"#)
        let avatar = try decode(MerchantAvatarResource.self, #"{"available":false,"styles":[],"job":{"jobId":8,"status":"unexpected"}}"#)
        XCTAssertEqual(voice.statusKey, "merchant.operations.review.unknown"); XCTAssertEqual(avatar.job?.statusKey, "merchant.operations.review.unknown")
    }
}

final class MerchantOperationsServiceTests: XCTestCase {
    private let accessJSON = #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:coop:manage","merchant:project:manage"]}"#
    private func access() throws -> MerchantOperationsAccess { try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(accessJSON.utf8)) }
    private func service(_ t: MerchantOperationsTransport) throws -> MerchantOperationsService { try .init(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!), transport: t) }
    private func envelope(_ json: String) -> String { "{\"code\":200,\"data\":\(json)}" }
    func testAccessUsesBodylessPOSTAndRawAuthorization() async throws {
        let t = MerchantOperationsTransport(); t.replies = [envelope(accessJSON)]
        _ = try await service(t).access(token: "synthetic-token")
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/prod-api/api/merchant/access/me"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token"); XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.timeoutInterval, 20); XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testProfileUsesEmptyMultipartAndChecksMerchantIdentity() async throws {
        let t = MerchantOperationsTransport(); t.replies = [envelope(MerchantOperationsFixtureData.storeJSON)]
        _ = try await service(t).document(.profile, access: access(), token: "synthetic-token")
        XCTAssertEqual(t.requests[0].url?.path, "/prod-api/api/merchant/info")
        XCTAssertTrue(t.requests[0].value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        t.replies = [envelope(#"{"id":99,"name":"Other store"}"#)]
        do { _ = try await service(t).document(.profile, access: access(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testDecorStoryGalleryCoopShareExactReadJSON() async throws {
        for destination in [MerchantOperationsDestination.decor, .story, .gallery, .cooperation] {
            let t = MerchantOperationsTransport(); t.replies = [envelope(MerchantOperationsFixtureData.storeJSON)]
            _ = try await service(t).document(destination, access: access(), token: "synthetic-token")
            XCTAssertEqual(t.requests[0].url?.path, "/prod-api/api/merchant/coop-profile")
            XCTAssertEqual(t.requests[0].httpBody, Data("{}".utf8))
        }
    }
    func testNPCExplicitNullMeansUnconfiguredButMissingDataIsMalformed() async throws {
        let t = MerchantOperationsTransport(); t.replies = [envelope("null")]
        let result = try await service(t).document(.character, access: access(), token: "synthetic-token")
        XCTAssertEqual(result, .draft(.character(.init())))
        XCTAssertEqual(t.requests[0].url?.path, "/prod-api/api/merchant/npc/profile")
        t.replies = [#"{"code":200}"#]
        do { _ = try await service(t).document(.character, access: access(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testCityCatalogUsesBodylessPOST() async throws {
        let t = MerchantOperationsTransport(); t.replies = [envelope(MerchantOperationsFixtureData.cityJSON)]
        _ = try await service(t).document(.cityNodes, access: access(), token: "synthetic-token")
        XCTAssertEqual(t.requests[0].url?.path, "/prod-api/api/merchant/city-node/list"); XCTAssertNil(t.requests[0].httpBody)
    }
    func testTemplateCatalogKeepsExactFirstPageForm() async throws {
        let t = MerchantOperationsTransport(); t.replies = [envelope(MerchantOperationsFixtureData.templatesJSON)]
        _ = try await service(t).document(.templates, access: access(), token: "synthetic-token")
        let request = t.requests[0], body = String(decoding: t.requests[0].httpBody!, as: UTF8.self)
        XCTAssertEqual(request.url?.path, "/prod-api/api/template/my-list")
        for (key, value) in ["is_quote":"", "keyword":"", "category_id":"", "pageNum":"1", "pageSize":"100"] { XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n")) }
        t.replies = [envelope("{\"rows\":\(MerchantOperationsFixtureData.templatesJSON)}")]
        let wrapped = try await service(t).document(.templates, access: access(), token: "synthetic-token")
        if case .templates(let rows) = wrapped { XCTAssertEqual(rows.count, 2) } else { XCTFail() }
    }
    func testTemplateDetailNeverUsesPublicInfoForPrivateAnswers() async throws {
        let t = MerchantOperationsTransport(); t.replies = [envelope(MerchantOperationsFixtureData.templateJSON)]
        _ = try await service(t).document(.template(71), access: access(), token: "synthetic-token")
        XCTAssertEqual(t.requests[0].url?.path, "/prod-api/api/template/myinfo")
        XCTAssertTrue(String(decoding: t.requests[0].httpBody!, as: UTF8.self).contains("name=\"id\"\r\n\r\n71\r\n"))
    }
    func testNewTemplateMakesNoDetailRequest() async throws {
        let t = MerchantOperationsTransport()
        let result = try await service(t).document(.template(nil), access: access(), token: "synthetic-token")
        XCTAssertEqual(result, .draft(.template(.init()))); XCTAssertTrue(t.requests.isEmpty)
    }
    func testDeniedAndLiveSaveUseZeroTransportRequests() async throws {
        let t = MerchantOperationsTransport(), s = try service(t)
        let denied = try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(#"{"active":false}"#.utf8))
        do { _ = try await s.document(.profile, access: denied, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        do { try await s.save(.template(.init()), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testRead403AndBusinessMessagesStayDistinct() async throws {
        let t = MerchantOperationsTransport(); t.replies = [#"{"code":403,"msg":"Denied"}"#]
        do { _ = try await service(t).access(token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        t.replies = [#"{"code":422,"msg":"Synthetic source message"}"#]
        do { _ = try await service(t).access(token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .rejected(code: 422, message: "Synthetic source message")) }
    }
}

@MainActor
final class MerchantOperationsCoordinatorTests: XCTestCase {
    private func edited(_ model: MerchantOperationsCoordinator) throws -> MerchantOperationsDraft {
        guard case .profile(var profile) = model.draft else { throw APIError.malformedResponse }; profile.name = "Edited synthetic shop"; return .profile(profile)
    }
    func testDraftChangeBackToBaselineIsNotDirty() async throws {
        let reader = MerchantOperationsFixtureReader(), model = MerchantOperationsCoordinator(reader: MerchantOperationsFixtureReader(), destination: .profile)
        _ = reader; await model.load(); let baseline = try XCTUnwrap(model.baseline)
        model.edit(try edited(model)); XCTAssertTrue(model.isDirty); model.edit(baseline); XCTAssertFalse(model.isDirty)
    }
    func testPrepareCancelDoesNotSend() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator
        model = .init(reader: reader, destination: .profile); await model.load(); model.edit(try edited(model)); model.prepare()
        XCTAssertNotNil(model.confirmation); model.cancelConfirmation(); XCTAssertNil(model.confirmation); XCTAssertEqual(reader.saveCount, 0)
    }
    func testFrozenExampleConfirmationIsSingleDispatch() async throws {
        let reader = MerchantOperationsFixtureReader(), model = MerchantOperationsCoordinator(reader: MerchantOperationsFixtureReader(), destination: .profile)
        _ = reader; await model.load(); model.edit(try edited(model)); model.prepare(); let confirmation = try XCTUnwrap(model.confirmation)
        await model.confirm(confirmation); await model.confirm(confirmation)
        XCTAssertTrue(model.exampleSaved); XCTAssertFalse(model.isDirty)
        XCTAssertEqual((model.reader as? MerchantOperationsFixtureReader)?.saveCount, 1)
    }
    func testEditingCancelsFrozenConfirmation() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator
        model = .init(reader: reader, destination: .profile); await model.load(); model.edit(try edited(model)); model.prepare()
        let confirmation = try XCTUnwrap(model.confirmation); model.edit(try XCTUnwrap(model.baseline)); await model.confirm(confirmation)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testConflictStopsExampleWrite() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator
        model = .init(reader: reader, destination: .profile); await model.load(); let changed = try edited(model); model.edit(changed); model.prepare()
        let confirmation = try XCTUnwrap(model.confirmation); reader.replace(.profile, with: .draft(changed)); await model.confirm(confirmation)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertEqual(model.issue, .key("merchant.operations.conflict"))
    }
    func testUnknownOutcomeRemainsLockedAcrossRefreshAndReentry() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator; reader.saveFailure = .outcomeUnknown
        model = .init(reader: reader, destination: .profile); await model.load(); model.edit(try edited(model)); model.prepare()
        await model.confirm(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.isLocked); XCTAssertFalse(model.exampleSaved)
        await model.load(); model.edit(try edited(model)); model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(reader.saveCount, 1)
        model.leaveScreen(); await model.load(); XCTAssertTrue(model.isLocked)
    }
    func testContentRejectionRetainsDraftAndServerMessage() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator
        reader.saveFailure = .rejected(code: 422, message: "Synthetic rejected text")
        model = .init(reader: reader, destination: .profile); await model.load(); model.edit(try edited(model)); model.prepare()
        await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertFalse(model.isLocked); XCTAssertTrue(model.isDirty); XCTAssertEqual(model.issue, .server("Synthetic rejected text"))
    }
    func testSignOutHidesOldContentAndPreventsConfirmation() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator
        model = .init(reader: reader, destination: .profile); await model.load(); model.edit(try edited(model)); model.prepare()
        let confirmation = try XCTUnwrap(model.confirmation); reader.signOut(); XCTAssertFalse(model.isCurrent)
        await model.confirm(confirmation); XCTAssertEqual(reader.saveCount, 0); await model.load(); XCTAssertNil(model.document)
    }
    func testServiceSessionSwitchBetweenAccessAndDocumentSendsNoSecondRead() async throws {
        let t = MerchantOperationsTransport()
        t.replies = [#"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}}"#]
        var session: MerchantOperationsSession? = try .init(accountID: 8, epoch: 1, token: "synthetic-token")
        let service = try MerchantOperationsService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com")!), transport: t)
        let reader = MerchantOperationsSessionReader(service: service, currentSession: { session })
        t.onSend = { session = nil }
        do { _ = try await reader.document(.profile); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testLiveReaderNeverAllowsExampleMutation() async {
        let reader = MerchantOperationsSessionReader(service: nil, currentSession: { nil })
        do { try await reader.saveExample(.template(.init())); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
    }
}

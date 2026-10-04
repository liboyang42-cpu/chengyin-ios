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
        reader.saveFailure = nil // A now-working transport does not authorize replay.
        await model.load(); model.edit(try edited(model)); model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(reader.saveCount, 1)
        XCTAssertTrue(model.isLocked); XCTAssertEqual(model.draft, model.baseline); XCTAssertFalse(model.canReview)
        // Even a readback matching the attempted save is not its acknowledgment.
        reader.replace(.profile, with: .draft(try edited(model)))
        model.leaveScreen(); await model.load(); XCTAssertTrue(model.isLocked)
        model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(reader.saveCount, 1); XCTAssertFalse(model.exampleSaved)
    }
    func testPartialOutcomeRemainsLockedAcrossRefreshAndReentry() async throws {
        let reader = MerchantOperationsFixtureReader(); reader.saveFailure = .partial(acknowledgedSteps: 1)
        let model = MerchantOperationsCoordinator(reader: reader, destination: .story)
        await model.load()
        guard case .story(var story) = model.draft else { XCTFail("Expected story draft"); return }
        story.profile.description = "Edited synthetic story"; model.edit(.story(story)); model.prepare()
        await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(model.isLocked); XCTAssertEqual(model.issue, .key("merchant.operations.partialOutcome")); XCTAssertEqual(reader.saveCount, 1)
        await model.load(); XCTAssertTrue(model.isLocked); model.prepare(); XCTAssertNil(model.confirmation)
        model.leaveScreen(); await model.load(); XCTAssertTrue(model.isLocked); XCTAssertEqual(reader.saveCount, 1)
    }
    func testNotSentAllowsFreshReviewAfterRefresh() async throws {
        let reader = MerchantOperationsFixtureReader(); reader.saveFailure = .notSent
        let model = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        await model.load(); model.edit(try edited(model)); model.prepare()
        await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertFalse(model.isLocked); XCTAssertTrue(model.isDirty); XCTAssertEqual(reader.saveCount, 1)
        reader.saveFailure = nil
        await model.load(); model.edit(try edited(model)); model.prepare()
        XCTAssertFalse(model.isLocked); await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(model.exampleSaved); XCTAssertFalse(model.isLocked); XCTAssertEqual(reader.saveCount, 2)
    }
    func testContentRejectionRetainsDraftAndServerMessage() async throws {
        let reader = MerchantOperationsFixtureReader(), model: MerchantOperationsCoordinator
        reader.saveFailure = .rejected(code: 422, message: "Synthetic rejected text")
        model = .init(reader: reader, destination: .profile); await model.load(); model.edit(try edited(model)); model.prepare()
        await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertFalse(model.isLocked); XCTAssertTrue(model.isDirty); XCTAssertEqual(model.issue, .server("Synthetic rejected text"))
        reader.saveFailure = nil; model.prepare(); await model.confirm(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(model.exampleSaved); XCTAssertFalse(model.isLocked); XCTAssertEqual(reader.saveCount, 2)
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

final class MerchantProfileBenefitsContractTests: XCTestCase {
    private func profile(_ json: String) throws -> MerchantStoreProfile {
        try JSONDecoder().decode(MerchantStoreProfile.self, from: Data(json.utf8))
    }
    func testBenefitsAreDistinctAndNeverCopiedFromMerchandise() throws {
        let value = try profile(#"{"id":31,"derivatives":"Merchandise","derivativeBenefits":"Route stamp"}"#)
        XCTAssertEqual(value.derivatives, "Merchandise")
        XCTAssertEqual(value.derivativeBenefits, "Route stamp")
        let draft = MerchantOperationsDraft.profile(value)
        let request = try XCTUnwrap(draft.previews().first)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.json) as? [String: Any])
        XCTAssertEqual(request.path, "api/merchant/update")
        XCTAssertEqual(fields["derivativeBenefits"] as? String, "Route stamp")
        XCTAssertEqual(fields["derivatives"] as? String, "Merchandise")
        XCTAssertNil(fields["phone"]); XCTAssertNil(fields["businessStatus"]); XCTAssertNil(fields["memberId"])
        XCTAssertTrue(draft.reviewLines.contains(.init("derivativeBenefits", "Route stamp")))
    }
    func testMissingAndNullAreOmittedButExplicitEmptyClears() throws {
        for json in [#"{"id":31}"#, #"{"id":31,"derivativeBenefits":null}"#] {
            let value = try profile(json)
            XCTAssertNil(value.derivativeBenefits); XCTAssertNil(value.fields["derivativeBenefits"])
        }
        let empty = try profile(#"{"id":31,"derivativeBenefits":""}"#)
        XCTAssertEqual(empty.fields["derivativeBenefits"] as? String, "")
        XCTAssertThrowsError(try profile(#"{"id":31,"derivativeBenefits":7}"#))
    }
    func testBenefitsUseServerUTF16BoundaryWithoutTruncation() throws {
        var value = try profile(#"{"id":31}"#)
        value.derivativeBenefits = String(repeating: "😀", count: 50)
        XCTAssertNil(MerchantOperationsDraft.profile(value).blocker)
        XCTAssertNoThrow(try MerchantOperationsDraft.profile(value).previews())
        value.derivativeBenefits! += "😀"
        XCTAssertEqual(value.derivativeBenefits?.count, 51)
        XCTAssertEqual(MerchantOperationsDraft.profile(value).blocker, "merchant.operations.benefitsLimit")
        XCTAssertThrowsError(try MerchantOperationsDraft.profile(value).previews())
    }
    func testStoryDoesNotResubmitIndependentBenefits() throws {
        var value = try JSONDecoder().decode(MerchantStorefront.self, from: Data(MerchantOperationsFixtureData.storeJSON.utf8))
        value.profile.derivativeBenefits = "Preserved independent value"
        value.profile.description = "Edited story"
        let request = try XCTUnwrap(MerchantOperationsDraft.story(value).previews().last)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.json) as? [String: Any])
        XCTAssertNil(fields["derivativeBenefits"])
    }
}

@MainActor
private final class ProfileReadbackReader: MerchantOperationsReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    let isOfflineExample = false
    let canSave = true
    let fixture = MerchantOperationsFixtureReader()
    var saved: MerchantOperationsDraft?
    var returned: MerchantOperationsDraft?
    var readbackError: Error?
    var saveError: MerchantOperationsFailure?
    var onReadback: (() -> Void)?
    var onSave: (() -> Void)?
    var saves = 0
    func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        if let saved {
            onReadback?()
            if let readbackError { throw readbackError }
            return .draft(returned ?? saved)
        }
        return try await fixture.document(destination)
    }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws {
        saves += 1; onSave?()
        if let saveError { throw saveError }
        saved = draft
    }
}

@MainActor
final class MerchantProfileBenefitsFlowTests: XCTestCase {
    private func prepared(_ reader: ProfileReadbackReader) async throws -> (MerchantOperationsCoordinator, MerchantOperationsConfirmation) {
        let model = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        await model.load()
        guard case .profile(var value) = model.draft else { throw APIError.malformedResponse }
        value.derivativeBenefits = "Route stamp"
        model.edit(.profile(value)); model.prepare()
        return (model, try XCTUnwrap(model.confirmation))
    }
    func testSaveReadsAuthoritativeStateAndReopensWithoutResending() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        guard case .profile(var server) = confirmation.draft else { XCTFail(); return }
        server.derivativeBenefits = "Current server value"
        reader.returned = .profile(server)
        await model.confirm(confirmation)
        XCTAssertEqual(model.draft, .profile(server)); XCTAssertEqual(model.baseline, .profile(server))
        XCTAssertFalse(model.isDirty); XCTAssertFalse(model.isLocked)
        XCTAssertEqual(model.issue, .key("merchant.operations.profileReadback"))
        await model.confirm(confirmation)
        model.leaveScreen(); await model.load()
        XCTAssertEqual(model.draft, .profile(server)); XCTAssertEqual(reader.saves, 1)
    }
    func testAcknowledgedReadbackFailureHidesUnverifiedValuesAndRetryOnlyReads() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        reader.readbackError = APIError.malformedResponse
        await model.confirm(confirmation)
        XCTAssertEqual(model.issue, .key("merchant.operations.profileReadbackFailed"))
        XCTAssertNil(model.document); XCTAssertNil(model.draft); XCTAssertNil(model.baseline)
        XCTAssertFalse(model.isLocked); XCTAssertFalse(model.canReview)
        await model.confirm(confirmation)
        XCTAssertEqual(reader.saves, 1)
        reader.readbackError = nil; await model.load()
        XCTAssertEqual(model.draft, confirmation.draft); XCTAssertEqual(reader.saves, 1)
    }
    func testScopeChangeDuringReadbackCannotRestoreOldProfile() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        reader.onReadback = { reader.scope = UUID() }
        await model.confirm(confirmation)
        XCTAssertFalse(model.isCurrent); XCTAssertNil(model.document); XCTAssertNil(model.draft)
        XCTAssertFalse(model.canReview); XCTAssertEqual(reader.saves, 1)
    }
    func testLeavingDuringReadbackCannotRestoreProfile() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        reader.onReadback = { model.leaveScreen() }
        await model.confirm(confirmation)
        XCTAssertNil(model.document); XCTAssertNil(model.draft); XCTAssertFalse(model.isCurrent)
        XCTAssertEqual(reader.saves, 1)
    }
    func testUnknownWriteRemainsLockedAndDoesNotReadBackAsAcknowledged() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        reader.saveError = .outcomeUnknown
        await model.confirm(confirmation)
        XCTAssertTrue(model.isLocked); XCTAssertEqual(model.issue, .key("merchant.operations.unknownOutcome"))
        XCTAssertNil(reader.saved); await model.load(); XCTAssertTrue(model.isLocked)
        XCTAssertFalse(model.canReview); XCTAssertEqual(reader.saves, 1)
    }
    func testLateOldWriteFailureCannotUnlockInvalidatedCoordinator() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        reader.saveError = .notSent
        reader.onSave = { model.leaveScreen(); reader.scope = UUID() }
        await model.confirm(confirmation)
        XCTAssertNil(model.document); XCTAssertNil(model.draft); XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.isLocked); XCTAssertFalse(model.isCurrent)
        XCTAssertEqual(reader.saves, 1)
    }
    func testBenefitsChangeParticipatesInFreshBaselineConflictCheck() async throws {
        let reader = ProfileReadbackReader()
        let (model, confirmation) = try await prepared(reader)
        guard case .profile(var changed) = model.baseline else { XCTFail(); return }
        changed.derivativeBenefits = "Changed elsewhere"
        reader.fixture.replace(.profile, with: .draft(.profile(changed)))
        await model.confirm(confirmation)
        XCTAssertEqual(model.issue, .key("merchant.operations.conflict")); XCTAssertEqual(reader.saves, 0)
    }
}

@MainActor
final class MerchantProfileViewerRevisionTests: XCTestCase {
    private func session(_ revision: UInt64) throws -> MerchantOperationsSession {
        try .init(accountID: 8, epoch: 4, token: "synthetic-token", storageNamespace: "example", viewerRevision: revision)
    }
    func testRoleRevisionAndABAChangeScopeWithoutChangingJournalOwner() throws {
        let first = try session(1), changed = try session(2), restored = try session(3)
        var current: MerchantOperationsSession? = first
        let reader = MerchantOperationsSessionReader(service: nil, currentSession: { current })
        let firstScope = reader.scope
        current = changed; XCTAssertNotEqual(reader.scope, firstScope)
        let changedScope = reader.scope
        current = restored; XCTAssertNotEqual(reader.scope, firstScope); XCTAssertNotEqual(reader.scope, changedScope)
        XCTAssertEqual(first.ownerKey, changed.ownerKey); XCTAssertEqual(first.ownerKey, restored.ownerKey)
        XCTAssertEqual(first.epoch, changed.epoch)
    }
    func testRoleRevisionDuringDocumentReadDropsLateResponseAndResetsBusyAfterLoad() async throws {
        let transport = MerchantOperationsTransport()
        transport.replies = [
            #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}}"#,
            "{\"code\":200,\"data\":\(MerchantOperationsFixtureData.storeJSON)}"
        ]
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(transport.replies[0].utf8)) as? [String: Any])
        let accessData = try JSONSerialization.data(withJSONObject: XCTUnwrap(envelope["data"]))
        let access = try JSONDecoder().decode(MerchantOperationsAccess.self, from: accessData)
        XCTAssertEqual(access.identity.role, .owner)
        XCTAssertTrue(access.allows(.profile))
        var current: MerchantOperationsSession? = try session(1)
        let changed = try session(2)
        let service = try MerchantOperationsService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com")!), transport: transport)
        let reader = MerchantOperationsSessionReader(service: service, currentSession: { current })
        let model = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        transport.onSend = { if transport.requests.count == 2 { current = changed } }
        await model.load()
        XCTAssertNil(model.document); XCTAssertNil(model.draft); XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.isCurrent); XCTAssertFalse(model.canReview)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/merchant/access/me", "/api/merchant/info"])
        XCTAssertEqual(current?.viewerRevision, 2)
    }
    func testScopeChangeBeforeConfirmationPreventsWrite() async throws {
        let reader = ProfileReadbackReader()
        let model = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        await model.load()
        guard case .profile(var profile) = model.draft else { XCTFail(); return }
        profile.derivativeBenefits = "Route stamp"; model.edit(.profile(profile)); model.prepare()
        let confirmation = try XCTUnwrap(model.confirmation)
        reader.scope = UUID()
        await model.confirm(confirmation)
        XCTAssertEqual(reader.saves, 0); XCTAssertFalse(model.canReview)
        model.invalidate(); XCTAssertFalse(model.isBusy); XCTAssertNil(model.confirmation)
    }
}

@MainActor
final class MerchantStoreHoursFlowTests: XCTestCase {
    func testHoursReviewCancellationFrozenSaveAndAuthoritativeReadback() async throws {
        let reader = ProfileReadbackReader()
        let model = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        await model.load()
        guard case .profile(var profile) = model.draft else { XCTFail(); return }
        profile.businessTimeReplacement = "周一、五 22:00-次日01:30"
        model.edit(.profile(profile)); model.prepare()
        let cancelled = try XCTUnwrap(model.confirmation)
        model.cancelConfirmation(); await model.confirm(cancelled)
        XCTAssertEqual(reader.saves, 0)
        model.prepare(); let review = try XCTUnwrap(model.confirmation)
        XCTAssertTrue(review.draft.reviewLines.contains { $0.key == "merchant.operations.businessTime" && $0.value == "周一、五 22:00-次日01:30" })
        let server = try JSONDecoder().decode(MerchantStoreProfile.self, from: Data(#"{"id":31,"businessTime":"周一、五 22:00-次日01:30"}"#.utf8))
        reader.returned = .profile(server)
        await model.confirm(review)
        XCTAssertEqual(model.draft, .profile(server)); XCTAssertNil(server.businessTimeReplacement)
        XCTAssertFalse(model.isDirty); XCTAssertEqual(reader.saves, 1)
        await model.confirm(review); XCTAssertEqual(reader.saves, 1)
    }
    func testHoursScopeChangeAndUnknownOutcomeDoNotResend() async throws {
        let reader = ProfileReadbackReader()
        let model = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        await model.load()
        guard case .profile(var profile) = model.draft else { XCTFail(); return }
        profile.businessTimeReplacement = "周一至周日 10:00-22:00"
        model.edit(.profile(profile)); model.prepare()
        let review = try XCTUnwrap(model.confirmation)
        reader.saveError = .outcomeUnknown
        await model.confirm(review)
        XCTAssertTrue(model.isLocked); XCTAssertEqual(reader.saves, 1)
        await model.confirm(review); XCTAssertEqual(reader.saves, 1)
        reader.scope = UUID(); model.invalidate()
        XCTAssertNil(model.draft); XCTAssertNil(model.confirmation)
        await model.confirm(review); XCTAssertEqual(reader.saves, 1)
    }
}

final class MerchantBusinessStatusContractTests: XCTestCase {
    func testExactBinaryResponseRejectsMissingNullStringBooleanAndUnknown() throws {
        for raw in ["0", "1"] {
            let value = try JSONDecoder().decode(MerchantBusinessStatusDocument.self, from: Data("{\"businessStatus\":\(raw)}".utf8))
            XCTAssertEqual(value.businessStatus.rawValue, Int(raw))
        }
        for json in ["{}", #"{"businessStatus":null}"#, #"{"businessStatus":"1"}"#, #"{"businessStatus":true}"#, #"{"businessStatus":2}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantBusinessStatusDocument.self, from: Data(json.utf8)))
        }
    }
    func testExactFormWhitelistAndSharedReplayLock() throws {
        let draft = MerchantOperationsDraft.businessStatus(try .init(merchantID: 31, status: .closed))
        let request = try XCTUnwrap(draft.previews().first)
        XCTAssertEqual(request.path, "api/merchant/business-status/update")
        XCTAssertEqual(request.form, ["business_status": "0"])
        XCTAssertEqual(draft.reviewLines, [.init("businessStatus", "0")])
        XCTAssertEqual(draft.destination.pendingTarget, MerchantOperationsDestination.profile.pendingTarget)
        XCTAssertThrowsError(try MerchantStoreBusinessStatus(merchantID: 0, status: .open))
    }
    func testOwnerRoleAndBasicReadDoNotGrantStatusEditing() throws {
        for permissions in [[], ["merchant:basic:read"], ["merchant:coop:manage"]] {
            let data = try JSONSerialization.data(withJSONObject: ["active": true, "merchant": ["id":31], "roleCode":"MERCHANT_OWNER", "permissions": permissions])
            let access = try JSONDecoder().decode(MerchantOperationsAccess.self, from: data)
            XCTAssertFalse(access.allows(.businessStatus))
        }
    }
}

@MainActor private final class BusinessStatusJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantBusinessStatusFlowTests: XCTestCase {
    private func status(_ value: MerchantBusinessStatus, owner: Int = 31) throws -> MerchantOperationsDraft {
        .businessStatus(try .init(merchantID: owner, status: value))
    }
    private func prepared(_ reader: ProfileReadbackReader) async throws -> (MerchantOperationsCoordinator, MerchantOperationsConfirmation) {
        let model = MerchantOperationsCoordinator(reader: reader, destination: .businessStatus)
        await model.load(); model.edit(try status(.closed)); model.prepare()
        return (model, try XCTUnwrap(model.confirmation))
    }
    func testClosedStatusSurvivesUnrelatedProfileHoursSave() async throws {
        let reader = MerchantOperationsFixtureReader()
        try await reader.saveExample(try status(.closed))
        guard case .draft(.profile(var profile)) = try await reader.document(.profile) else { return XCTFail("Expected profile") }
        profile.businessTimeReplacement = "周一、二、三、四、五 09:00-18:00"
        try await reader.saveExample(.profile(profile))
        let result = try await reader.document(.businessStatus)
        XCTAssertEqual(result, .draft(try status(.closed)))
    }
    func testCancelAndStaleConfirmationSendNothing() async throws {
        let reader = ProfileReadbackReader(); let (model, confirmation) = try await prepared(reader)
        model.cancelConfirmation(); await model.confirm(confirmation); XCTAssertEqual(reader.saves, 0)
        model.prepare(); let newer = try XCTUnwrap(model.confirmation)
        model.edit(try status(.open)); await model.confirm(newer); XCTAssertEqual(reader.saves, 0)
    }
    func testAuthoritativeReadbackOverridesSubmittedValueAndDoubleConfirmDoesNotResend() async throws {
        let reader = ProfileReadbackReader(); reader.returned = try status(.open)
        let (model, confirmation) = try await prepared(reader)
        await model.confirm(confirmation); await model.confirm(confirmation)
        XCTAssertEqual(reader.saves, 1); XCTAssertEqual(model.draft, try status(.open))
        XCTAssertFalse(model.isDirty); XCTAssertFalse(model.isLocked)
        XCTAssertEqual(model.issue, .key("merchant.operations.statusReadback"))
    }
    func testAcknowledgedReadbackFailureClearsStateWithoutUnknownWriteOrRetry() async throws {
        let reader = ProfileReadbackReader(); reader.readbackError = APIError.malformedResponse
        let (model, confirmation) = try await prepared(reader); await model.confirm(confirmation)
        XCTAssertNil(model.draft); XCTAssertNil(model.baseline); XCTAssertFalse(model.isLocked)
        XCTAssertEqual(model.issue, .key("merchant.operations.statusReadbackFailed"))
        await model.confirm(confirmation); XCTAssertEqual(reader.saves, 1)
    }
    func testReadbackCannotAdoptDifferentMerchantOwner() async throws {
        let reader = ProfileReadbackReader(); reader.returned = try status(.closed, owner: 32)
        let (model, confirmation) = try await prepared(reader); await model.confirm(confirmation)
        XCTAssertNil(model.draft); XCTAssertEqual(model.issue, .key("merchant.operations.statusReadbackFailed"))
    }
    func testUnknownWriteRemainsLockedAfterRefreshAndReentry() async throws {
        let reader = ProfileReadbackReader(); reader.saveError = .outcomeUnknown
        let (model, confirmation) = try await prepared(reader); await model.confirm(confirmation)
        model.leaveScreen(); await model.load(); model.edit(try status(.closed)); model.prepare()
        XCTAssertTrue(model.isLocked); XCTAssertNil(model.confirmation); XCTAssertEqual(reader.saves, 1)
    }
    func testRoleSessionChangeBeforeConfirmOrDuringReadbackDropsResult() async throws {
        let reader = ProfileReadbackReader(); let (model, confirmation) = try await prepared(reader)
        reader.scope = UUID(); await model.confirm(confirmation); XCTAssertEqual(reader.saves, 0)
        let next = ProfileReadbackReader(); let (nextModel, nextConfirmation) = try await prepared(next)
        next.onReadback = { next.scope = UUID() }
        await nextModel.confirm(nextConfirmation); XCTAssertNil(nextModel.draft); XCTAssertFalse(nextModel.isCurrent)
    }
    func testConflictIncludingOwnerChangeBlocksDispatch() async throws {
        let reader = ProfileReadbackReader(); let (model, confirmation) = try await prepared(reader)
        reader.fixture.replace(.businessStatus, with: .draft(try status(.open, owner: 32)))
        await model.confirm(confirmation); XCTAssertEqual(reader.saves, 0)
        XCTAssertEqual(model.issue, .key("merchant.operations.conflict"))
    }
    func testDormantServiceExactFormAndUnknownPersistentReplayLock() async throws {
        let transport = MerchantOperationsTransport()
        let config = try APIConfiguration(baseURL: URL(string: "https://api.example.com")!)
        let service = MerchantOperationsService(configuration: config, transport: transport)
        let grant = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "fixture", accountID: 8, paths: ["api/merchant/business-status/update"])
        let journal = BusinessStatusJournal()
        let baseline = try status(.open), draft = try status(.closed)
        let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:basic:read"]}}"#
        transport.replies = [access, #"{"code":200,"data":{"businessStatus":1}}"#, #"{"code":200}"#]
        _ = try await service.save(draft, token: "synthetic-token", approval: grant, namespace: "fixture", accountID: 8, baseline: baseline, journal: journal, checkSession: {})
        XCTAssertEqual(transport.requests.count, 3)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.url?.path, "/api/merchant/business-status/update")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        XCTAssertEqual(request.httpBody, Data("business_status=0".utf8)); XCTAssertNil(journal.record)
        transport.replies = [access, #"{"code":200,"data":{"businessStatus":1}}"#, "invalid"]
        do { _ = try await service.save(draft, token: "synthetic-token", approval: grant, namespace: "fixture", accountID: 8, baseline: baseline, journal: journal, checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .outcomeUnknown) }
        XCTAssertNotNil(journal.record); let count = transport.requests.count
        do { _ = try await service.save(draft, token: "synthetic-token", approval: grant, namespace: "fixture", accountID: 8, baseline: baseline, journal: journal, checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .outcomeUnknown) }
        XCTAssertEqual(transport.requests.count, count)
    }
    func testMissingGrantAndRevokedProfilePermissionSendNoWrite() async throws {
        let transport = MerchantOperationsTransport(), config = try APIConfiguration(baseURL: URL(string: "https://api.example.com")!)
        let service = MerchantOperationsService(configuration: config, transport: transport)
        do { _ = try await service.save(try status(.closed), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
        let grant = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "fixture", accountID: 8, paths: ["api/merchant/business-status/update"])
        transport.replies = [#"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:basic:read"]}}"#]
        do { _ = try await service.save(try status(.closed), token: "synthetic-token", approval: grant, namespace: "fixture", accountID: 8, baseline: try status(.open), journal: BusinessStatusJournal(), checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 1)
    }
}

@MainActor private final class DelayedBusinessStatusReader: MerchantOperationsReading {
    var scope = UUID()
    let isConfigured = true
    let isAuthenticated = true
    let isOfflineExample = true
    let fixture = MerchantOperationsFixtureReader()
    var continuation: CheckedContinuation<MerchantOperationsDocument, Error>?
    var delay = true
    func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        if delay { delay = false; return try await withCheckedThrowingContinuation { continuation = $0 } }
        return try await fixture.document(destination)
    }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
}
@MainActor final class MerchantBusinessStatusInterruptionTests: XCTestCase {
    func testLatePriorReadCannotReplaceNewScopeDocument() async throws {
        let reader = DelayedBusinessStatusReader(), model: MerchantOperationsCoordinator
        model = .init(reader: reader, destination: .businessStatus)
        let old = Task { await model.load() }
        while reader.continuation == nil { await Task.yield() }
        model.leaveScreen(); reader.scope = UUID(); await model.load()
        let current = model.document
        reader.continuation?.resume(returning: .draft(.businessStatus(try .init(merchantID: 99, status: .closed))))
        await old.value
        XCTAssertEqual(model.document, current)
        XCTAssertEqual(model.draft, .businessStatus(try .init(merchantID: 31, status: .open)))
    }
    func testRoleABAEpochPreventsSecondRead() async throws {
        let transport = MerchantOperationsTransport()
        transport.replies = [#"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:basic:read"]}}"#]
        var session: MerchantOperationsSession? = try .init(accountID: 8, epoch: 1, token: "synthetic-token", storageNamespace: "fixture", viewerRevision: 1)
        let original = session
        let config = try APIConfiguration(baseURL: URL(string: "https://api.example.com")!)
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: config, transport: transport), currentSession: { session })
        transport.onSend = {
            // Same account/token and restored role still carries a new authority revision.
            session = try? .init(accountID: 8, epoch: 1, token: "synthetic-token", storageNamespace: "fixture", viewerRevision: 3)
        }
        do { _ = try await reader.document(.businessStatus); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNotEqual(session, original); XCTAssertEqual(transport.requests.count, 1)
    }
}

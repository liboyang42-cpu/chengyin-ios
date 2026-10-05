import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CoopRelationDiscoveryTests: XCTestCase {
    func testBothListsPreserveOrderAndMerchantOwnerNamespace() throws {
        let value = try CoopRelationDiscovery(relationFixture(merchants: [merchant(8, 41), merchant(41, 8)], clubs: [club(41)]))
        XCTAssertEqual(value.merchants.map(\.rowID), [8, 41])
        XCTAssertEqual(value.merchants.map(\.route), [.merchant(PublicMerchantOwnerID(41)!), .merchant(PublicMerchantOwnerID(8)!)])
        XCTAssertEqual(value.clubs.first?.route, .club(41))
    }
    func testClubsOnlyAndTrueEmptyAreDistinctFromMalformedLists() throws {
        XCTAssertEqual(try CoopRelationDiscovery(relationFixture(clubs: [club(12)])).clubs.count, 1)
        let empty = try CoopRelationDiscovery(relationFixture())
        XCTAssertTrue(empty.merchants.isEmpty); XCTAssertFalse(empty.hasInvalidRows(.merchants))
        for invalid: CoopFlowJSON in [.null, .object([:]), .object(["relations": .array([]), "discovery": .object(["merchants": .array([])])]), .object(["relations": .array([]), "discovery": .object(["merchants": .array([]), "clubs": .object([:])])])] {
            XCTAssertThrowsError(try CoopRelationDiscovery(invalid))
        }
    }
    func testPartialInvalidRowsNeverBorrowAnIdentity() throws {
        let value = try CoopRelationDiscovery(relationFixture(merchants: [.null, .object(["id": .id(41), "name": .string("Missing owner")]), merchant(8, 41)], clubs: [.object(["id": .id(-2), "name": .string("Invalid club")]), club(9)]))
        XCTAssertEqual(value.merchants.map(\.id), [1, 2]); XCTAssertEqual(value.invalidMerchantCount, 2)
        XCTAssertNil(value.merchants[0].route); XCTAssertNil(value.clubs[0].route)
        XCTAssertTrue(value.hasInvalidRows(.clubs))
        for identity: CoopFlowJSON in [.bool(true), .number(1.5), .id(0), .id(-1), .string("invalid"), .null] {
            let item: CoopFlowJSON = .object(["id": .id(8), "memberId": identity, "name": .string("Identity test")])
            XCTAssertNil(try CoopRelationDiscovery(relationFixture(merchants: [item])).merchants.first?.route)
        }
    }
    func testImagesUseExactSourceFieldsAndNoCategoryIDLabel() throws {
        let item: CoopFlowJSON = .object(["id": .id(8), "memberId": .id(41), "name": .string(" Shop "), "coverImage": .string(" /cover "), "cover": .string("wrong"), "logo": .string("logo"), "categoryId": .id(9), "sysCategoryList": .array([.object(["categoryName": .string("Books")])])])
        let row = try XCTUnwrap(CoopRelationDiscovery(relationFixture(merchants: [item])).merchants.first)
        XCTAssertEqual(row.name, "Shop"); XCTAssertEqual(row.cover, "/cover"); XCTAssertEqual(row.logo, "logo"); XCTAssertEqual(row.category, "Books")
        XCTAssertEqual(try CoopRelationDiscovery(relationFixture(clubs: [.object(["id": .id(9), "name": .string("Club"), "cover": .string("club-cover")])])).clubs.first?.cover, "club-cover")
    }
    func testDisplayContextRequiresPositiveTopicAndDoesNotCarryAuthority() {
        XCTAssertEqual(CoopRelationDisplayContext(topicID: 0, topicName: "ignored", chapterID: 4), CoopRelationDisplayContext())
        let context = CoopRelationDisplayContext(topicID: 3, topicName: " Walk ", chapterID: 5)
        XCTAssertEqual(context.topicID, 3); XCTAssertEqual(context.topicName, "Walk"); XCTAssertEqual(context.chapterID, 5)
        XCTAssertNil(CoopRelationDisplayContext(topicID: 3, chapterID: -1).chapterID)
    }
}
private func merchant(_ row: Int, _ owner: Int) -> CoopFlowJSON { .object(["id": .id(row), "memberId": .id(owner), "name": .string("Merchant \(row)")]) }
private func club(_ id: Int) -> CoopFlowJSON { .object(["id": .id(id), "name": .string("Club \(id)")]) }
private func relationFixture(merchants: [CoopFlowJSON] = [], clubs: [CoopFlowJSON] = []) -> CoopFlowJSON {
    .object(["relations": .array([]), "discovery": .object(["merchants": .array(merchants), "clubs": .array(clubs)])])
}
@MainActor private final class RelationReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID: 1, epoch: 1, token: "fixture")
    var value = relationFixture(merchants: [merchant(8, 41)], clubs: [club(9)])
    var readHook: (() async throws -> Void)?
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { try await readHook?(); return value }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
@MainActor final class CoopRelationDiscoveryScopeTests: XCTestCase {
    private let scope = CoopRelationProfileScope(merchantScope: UUID(), clubIdentity: .init(accountID: 1, epoch: 1), sessionRevision: 1, contentRevision: 1)
    func testSelectionRequiresExactReaderSnapshotContextAndDestinationScope() async throws {
        let reader = RelationReader(), model = CoopRelationDiscoveryModel(), context = CoopRelationDisplayContext(topicID: 3)
        await model.load(reader: reader)
        let row = try XCTUnwrap(model.value?.merchants.first)
        let selection = try XCTUnwrap(model.selection(row: row, reader: reader, scope: scope, context: context))
        XCTAssertTrue(model.isCurrent(selection, reader: reader, scope: scope, context: context))
        XCTAssertFalse(model.isCurrent(selection, reader: RelationReader(), scope: scope, context: context))
        XCTAssertFalse(model.isCurrent(selection, reader: reader, scope: scope, context: .init(topicID: 4)))
        let replacement = CoopRelationProfileScope(merchantScope: scope.merchantScope, clubIdentity: scope.clubIdentity, sessionRevision: 1, contentRevision: 2)
        XCTAssertFalse(model.isCurrent(selection, reader: reader, scope: replacement, context: context))
        await model.load(reader: reader)
        XCTAssertFalse(model.isCurrent(selection, reader: reader, scope: scope, context: context))
    }
    func testNavigationDisappearancePreservesAcceptedRowsButRefreshReplacesThem() async throws {
        let reader = RelationReader(), model = CoopRelationDiscoveryModel()
        await model.load(reader: reader)
        let row = try XCTUnwrap(model.value?.clubs.first)
        let selection = try XCTUnwrap(model.selection(row: row, reader: reader, scope: scope, context: .init()))
        model.leaveScreen()
        XCTAssertTrue(model.isCurrent(selection, reader: reader, scope: scope, context: .init()))
        reader.value = relationFixture(clubs: [club(10)])
        await model.load(reader: reader)
        XCTAssertFalse(model.isCurrent(selection, reader: reader, scope: scope, context: .init()))
        XCTAssertEqual(model.value?.clubs.first?.route, .club(10))
    }
    func testSessionTokenEpochAndSignOutInvalidateCards() async throws {
        let reader = RelationReader(), model = CoopRelationDiscoveryModel()
        let sessions: [CoopFlowSession?] = [nil, try .init(accountID: 2, epoch: 1, token: "fixture"), try .init(accountID: 1, epoch: 2, token: "fixture"), try .init(accountID: 1, epoch: 1, token: "replacement")]
        for session in sessions {
            reader.session = try .init(accountID: 1, epoch: 1, token: "fixture")
            await model.load(reader: reader)
            let row = try XCTUnwrap(model.value?.merchants.first)
            reader.session = session
            XCTAssertFalse(model.isCurrent(reader: reader))
            XCTAssertNil(model.selection(row: row, reader: reader, scope: scope, context: .init()))
        }
    }
    func testStaleSuccessAndErrorCannotPublishAfterInvalidation() async {
        for fail in [false, true] {
            let reader = RelationReader(), model = CoopRelationDiscoveryModel()
            reader.readHook = { model.invalidate(); if fail { throw APIError.unauthorized } }
            await model.load(reader: reader)
            XCTAssertNil(model.value); XCTAssertFalse(model.failed); XCTAssertFalse(model.isLoading)
        }
    }
    func testMalformedResponseFailsWithoutFabricatedEmptyAndRetryRecovers() async {
        let reader = RelationReader(), model = CoopRelationDiscoveryModel()
        reader.value = .object([:]); await model.load(reader: reader)
        XCTAssertTrue(model.failed); XCTAssertNil(model.value)
        reader.value = relationFixture(clubs: [club(9)]); await model.load(reader: reader)
        XCTAssertFalse(model.failed); XCTAssertEqual(model.value?.clubs.count, 1)
    }
}
private final class RelationTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var value = relationFixture(clubs: [club(9)])
    var status = 200
    var hook: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); hook?()
        return (try CoopFlowJSON.object(["code": .id(status), "data": value]).canonical(), status)
    }
}
@MainActor final class CoopRelationDiscoveryServiceTests: XCTestCase {
    func testExistingJSONReadUsesLimitTenAndValidatesBothLists() async throws {
        let wire = RelationTransport(), session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        let service = CoopFlowService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        _ = try await service.read(.relations, session: session)
        let request = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.url?.path, "/api/merchant/relation-home"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try JSONDecoder().decode(CoopFlowJSON.self, from: XCTUnwrap(request.httpBody)), .object(["limit": .id(10)]))
        wire.value = .object(["relations": .array([]), "discovery": .object(["merchants": .array([])])])
        do { _ = try await service.read(.relations, session: session); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .malformed) }
    }
    func testDelayedUnauthorizedAfterContentScopeOrReloadCannotExpireSession() async throws {
        for invalidation in ["content", "reload", "disappear"] {
            let wire = RelationTransport(), model = CoopRelationDiscoveryModel()
            let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "same-token")
            var current = true, expired = 0
            let service = CoopFlowService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
            let reader = CoopFlowSessionReader(service: service, current: { session }, unauthorized: { _ in expired += 1 })
            wire.status = 401
            wire.hook = {
                if invalidation == "content" { current = false }
                else if invalidation == "reload" { model.invalidate() }
                else { model.leaveScreen() }
            }
            await model.load(reader: reader, isCurrent: { current })
            XCTAssertEqual(expired, 0, invalidation); XCTAssertNil(model.value); XCTAssertFalse(model.failed)
        }
    }
    func testObsoleteProfileSelectionRejectsDelayedClubUnauthorized() async throws {
        let flow = RelationReader(), model = CoopRelationDiscoveryModel()
        await model.load(reader: flow)
        let scope = CoopRelationProfileScope(merchantScope: UUID(), clubIdentity: .init(accountID: 1, epoch: 1), sessionRevision: 1, contentRevision: 1)
        let row = try XCTUnwrap(model.value?.clubs.first)
        let selection = try XCTUnwrap(model.selection(row: row, reader: flow, scope: scope, context: .init()))
        var active: UUID? = selection.id
        let wire = RelationTransport(), session = try ClubReadSession(accountID: 1, epoch: 1, token: "same")
        var expired = 0
        let service = ClubService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let reader = ClubSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        wire.status = 401; wire.hook = { active = nil }
        do {
            _ = try await reader.clubDetail(id: 9, isCurrent: {
                active == selection.id && model.isCurrent(selection, reader: flow, scope: scope, context: .init())
            })
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    func testClubScopeChangeAfterDetailPreventsSecondMembersRequest() async throws {
        let wire = RelationTransport(), session = try ClubReadSession(accountID: 1, epoch: 1, token: "same")
        var current = true
        wire.value = .object(["id": .id(9), "name": .string("Club"), "isOwner": .bool(true)])
        wire.hook = { current = false }
        let service = ClubService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let reader = ClubSessionReader(service: service, currentSession: { session })
        do { _ = try await reader.clubMembers(id: 9, isCurrent: { current }); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(wire.requests.first?.url?.path, "/api/club/detail")
    }
    func testClubReadScopeRejectsOldUnauthorizedBeforeCallback() async throws {
        let wire = RelationTransport()
        let session = try ClubReadSession(accountID: 1, epoch: 1, token: "same-token")
        var current = true, expired = 0
        let service = ClubService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let reader = ClubSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        wire.status = 401; wire.hook = { current = false }
        do { _ = try await reader.clubDetail(id: 9, isCurrent: { current }); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
        current = true
        do { _ = try await reader.clubMembers(id: 9, isCurrent: { current }); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
        current = true; wire.hook = nil
        do { _ = try await reader.clubDetail(id: 9, isCurrent: { current }); XCTFail() }
        catch { XCTAssertTrue((error as? ClubReadFailure)?.isUnauthorized == true) }
        XCTAssertEqual(expired, 1)
    }
    func testDelayedUnauthorizedFromOldSessionCannotExpireReplacement() async throws {
        let wire = RelationTransport()
        var session: CoopFlowSession? = try .init(accountID: 1, epoch: 1, token: "old")
        var expired = 0
        let service = CoopFlowService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let reader = CoopFlowSessionReader(service: service, current: { session }, unauthorized: { _ in expired += 1 })
        wire.status = 401
        wire.hook = { session = try! .init(accountID: 1, epoch: 2, token: "new") }
        do { _ = try await reader.read(.relations); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(expired, 0)
        wire.hook = nil
        do { _ = try await reader.read(.relations); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, 1)
    }
}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantClubDiscoveryTests: XCTestCase {
    private func locality(_ json: String) throws -> MerchantClubLocality {
        try JSONDecoder().decode(MerchantClubLocality.self, from: Data(json.utf8))
    }
    private func clubs(_ json: String = #"[{"id":1,"city":"A City"},{"id":2,"city":"B City"},{"id":3}]"#) throws -> [ClubRecord] {
        try JSONDecoder().decode([ClubRecord].self, from: Data(json.utf8))
    }
    private func scope(account: Int? = 7, epoch: UInt64 = 1, role: String? = "merchant", view: UInt64 = 1,
                       merchant: Int? = 31, revision: UInt64 = 1) -> ClubDiscoveryScope {
        .init(identity: .init(accountID: account, epoch: epoch), role: role, viewerRevision: view,
              merchantID: merchant, merchantRevision: revision)
    }
    func testCityWinsAndAddressIsTrimmedFallbackOnly() throws {
        XCTAssertEqual(try locality(#"{"id":31,"city":"  A City\n","address":"B City street"}"#).value, "A City")
        for city in ["null", "42", "{}", "[]", "true", "\"  \""] {
            XCTAssertEqual(try locality("{\"id\":31,\"city\":\(city),\"address\":\" B City street \"}").value, "B City street")
        }
        XCTAssertEqual(try locality(#"{"id":"31","city":" \n ","address":" B City street "}"#).value, "B City street")
    }
    func testSourceTrimIncludesBOMButDoesNotStripNEL() throws {
        XCTAssertEqual(try locality(#"{"id":31,"city":"\ufeff A City \ufeff"}"#).value, "A City")
        XCTAssertEqual(try locality(#"{"id":31,"city":"\u0085","address":"A City"}"#).value, "\u{0085}")
    }
    func testUnknownLocalityNeverInventsCoordinatesOrCity() throws {
        for json in [#"{"id":31}"#, #"{"id":31,"city":null,"address":null}"#,
                     #"{"id":31,"city":" ","address":" \n "}"#,
                     #"{"id":31,"city":false,"address":17,"locationLat":31,"locationLng":121}"#] {
            XCTAssertNil(try locality(json).value)
        }
        for id in ["null", "0", "-1", "true", "1.5", "\"wrong\""] {
            XCTAssertThrowsError(try locality("{\"id\":\(id),\"city\":\"A City\"}"))
        }
    }
    func testSourceSubstringAsymmetryOrderWhitespaceAndCaseArePreserved() throws {
        let local = try locality(#"{"id":31,"city":"A City"}"#)
        let rows = try clubs(#"[{"id":1,"city":"A City District"},{"id":2,"city":"A"},{"id":3,"address":"A City Lane"},{"id":4,"city":"B","address":"A City Lane"},{"id":5,"city":" ","address":"B"},{"id":6,"city":"a city"},{"id":7},{"id":8,"city":"","address":"A City"}]"#)
        // Source c.city = " " is truthy and reverse substring matches the space in A City.
        XCTAssertEqual(rows.filter(local.matches).map(\.id), [1, 2, 3, 5, 8])
        let address = try locality(#"{"id":31,"address":"A City Road 7"}"#)
        XCTAssertTrue(address.matches(try clubs(#"[{"id":1,"city":"A City"}]"#)[0]))
        XCTAssertFalse(address.matches(try clubs(#"[{"id":1,"address":"A City"}]"#)[0]))
    }
    func testFilterIsLiteralWithoutUnicodeNormalization() throws {
        let value = try locality(#"{"id":31,"city":"é"}"#)
        XCTAssertFalse(value.matches(try clubs(#"[{"id":1,"city":"e\u0301"}]"#)[0]))
        XCTAssertTrue(value.matches(try clubs(#"[{"id":1,"city":"é district"}]"#)[0]))
    }
    func testPlayersGuestsAndClubViewKeepEveryNearbyRowAndNeverBeginLocality() throws {
        let rows = try clubs()
        for context in [scope(role: "player"), scope(role: "club"), scope(role: nil), scope(account: nil)] {
            var state = MerchantClubDiscoveryState()
            XCTAssertNil(state.begin(in: context))
            XCTAssertEqual(state.nearby(rows, in: context), rows)
            XCTAssertEqual(state.phase(in: context), .idle)
        }
    }
    func testLoadingFailureAndUnknownRetainUnfilteredNearbyThenRetryFilters() throws {
        let rows = try clubs(), context = scope()
        var state = MerchantClubDiscoveryState()
        let first = try XCTUnwrap(state.begin(in: context))
        XCTAssertEqual(state.phase(in: context), .loading)
        XCTAssertEqual(state.nearby(rows, in: context), rows)
        XCTAssertTrue(state.fail(first, current: context))
        XCTAssertEqual(state.phase(in: context), .unavailable)
        XCTAssertEqual(state.nearby(rows, in: context), rows)
        let second = try XCTUnwrap(state.begin(in: context))
        XCTAssertTrue(state.receive(try locality(#"{"id":31}"#), for: second, current: context))
        XCTAssertEqual(state.phase(in: context), .unavailable)
        XCTAssertEqual(state.nearby(rows, in: context), rows)
        let third = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: third, current: context)
        XCTAssertEqual(state.phase(in: context), .ready)
        XCTAssertEqual(state.nearby(rows, in: context).map(\.id), [1])
        XCTAssertEqual(rows.map(\.id), [1, 2, 3])
    }
    func testSuccessfulLocalityCanHonestlyFilterToEmpty() throws {
        var state = MerchantClubDiscoveryState(); let context = scope()
        let request = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":31,"city":"Other City"}"#), for: request, current: context)
        XCTAssertEqual(state.phase(in: context), .ready)
        XCTAssertTrue(state.nearby(try clubs(), in: context).isEmpty)
    }
    func testEveryCurrentScopeDimensionRejectsOldSuccessAndFailureImmediately() throws {
        let original = scope(), result = try locality(#"{"id":31,"city":"A City"}"#), rows = try clubs()
        for replacement in [scope(account: 8), scope(epoch: 2), scope(role: "player"), scope(view: 2),
                            scope(merchant: 32), scope(revision: 2), scope(account: nil)] {
            var state = MerchantClubDiscoveryState()
            let old = try XCTUnwrap(state.begin(in: original))
            XCTAssertFalse(state.receive(result, for: old, current: replacement))
            XCTAssertFalse(state.fail(old, current: replacement))
            XCTAssertEqual(state.nearby(rows, in: replacement), rows)
            XCTAssertEqual(state.phase(in: replacement), .idle)
        }
    }
    func testRoleAndMerchantABARemainFencedByRevisions() throws {
        var state = MerchantClubDiscoveryState(); let original = scope()
        let old = try XCTUnwrap(state.begin(in: original))
        XCTAssertFalse(state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: old,
                                     current: scope(view: 3, revision: 3)))
    }
    func testReversedRetryCompletionCannotReplaceLatestOrMakeItFail() throws {
        var state = MerchantClubDiscoveryState(); let context = scope()
        let old = try XCTUnwrap(state.begin(in: context)), latest = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":31,"city":"B City"}"#), for: latest, current: context)
        XCTAssertFalse(state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: old, current: context))
        XCTAssertFalse(state.fail(old, current: context))
        XCTAssertEqual(state.nearby(try clubs(), in: context).map(\.id), [2])
    }
    func testMerchantMismatchFallsBackWithoutAdoptingAnotherMerchant() throws {
        var state = MerchantClubDiscoveryState(); let context = scope(), rows = try clubs()
        let request = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":32,"city":"A City"}"#), for: request, current: context)
        XCTAssertEqual(state.phase(in: context), .unavailable)
        XCTAssertEqual(state.nearby(rows, in: context), rows)
    }
    func testFirstTokenScopedResponseCanEstablishMerchantWithoutAnAccessCache() throws {
        var state = MerchantClubDiscoveryState(); let context = scope(merchant: nil)
        let request = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: request, current: context)
        XCTAssertEqual(state.nearby(try clubs(), in: context).map(\.id), [1])
    }
    func testDisappearRejectsPendingButKeepsReadyRowsForReturnNavigation() throws {
        var state = MerchantClubDiscoveryState(); let context = scope()
        let pending = try XCTUnwrap(state.begin(in: context))
        state.leaveScreen()
        XCTAssertFalse(state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: pending, current: context))
        XCTAssertEqual(state.phase(in: context), .idle)
        let current = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: current, current: context)
        state.leaveScreen()
        XCTAssertEqual(state.phase(in: context), .ready)
        XCTAssertEqual(state.nearby(try clubs(), in: context).map(\.id), [1])
    }
    func testEveryNewClubHomeSnapshotUsesCurrentLocalityWithoutMutatingMembership() throws {
        var state = MerchantClubDiscoveryState(); let context = scope()
        let request = try XCTUnwrap(state.begin(in: context))
        state.receive(try locality(#"{"id":31,"city":"A City"}"#), for: request, current: context)
        let rows = try clubs(#"[{"id":9,"city":"A City","isOwner":true,"isJoined":true,"viewerIsAdmin":true},{"id":10,"city":"B City"}]"#)
        let shown = state.nearby(rows, in: context)
        XCTAssertEqual(shown.map(\.id), [9]); XCTAssertTrue(shown[0].isOwner); XCTAssertTrue(shown[0].isJoined)
        XCTAssertTrue(shown[0].viewerIsAdmin)
        XCTAssertEqual(state.nearby(try clubs(), in: scope(role: "player")).map(\.id), [1, 2, 3])
    }
}

private final class MerchantClubLocalityTransport: HTTPTransport {
    var json = #"{"code":200,"data":{"id":31,"city":" A City ","address":"ignored"}}"#
    var status = 200
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), status) }
}
final class MerchantClubLocalityServiceTests: XCTestCase {
    private func service(_ transport: MerchantClubLocalityTransport) throws -> MerchantOnboardingService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://fixture.example.test/base/")!), transport: transport)
    }
    func testReusesOnlyExistingEmptyMultipartTokenScopedInfoRead() async throws {
        let transport = MerchantClubLocalityTransport()
        let result = try await service(transport).clubLocality(token: "fixture-token")
        XCTAssertEqual(result.merchantID, 31); XCTAssertEqual(result.value, "A City")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://fixture.example.test/base/api/merchant/info")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertFalse(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("name=") == true)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testNoApplicationMalformedPayloadAndForeignIDsNeverBecomeLocality() async throws {
        for json in [#"{"code":200,"applicationState":"NONE"}"#, #"{"code":200,"data":null}"#,
                     #"{"code":200,"data":[]}"#, #"{"code":200,"data":{"id":false,"city":"A City"}}"#] {
            let transport = MerchantClubLocalityTransport(); transport.json = json
            do { _ = try await service(transport).clubLocality(token: "fixture-token"); XCTFail("Accepted malformed locality") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testServerUnauthorizedForbiddenAndInvalidTokenStayFailuresWithoutRetry() async throws {
        let transport = MerchantClubLocalityTransport()
        transport.status = 401
        do { _ = try await service(transport).clubLocality(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        transport.status = 200; transport.json = #"{"code":403,"msg":"Permission denied"}"#
        do { _ = try await service(transport).clubLocality(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual((error as? MerchantOnboardingFailure)?.code, 403) }
        XCTAssertEqual(transport.requests.count, 2)
        do { _ = try await service(transport).clubLocality(token: ""); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(transport.requests.count, 2)
    }
}

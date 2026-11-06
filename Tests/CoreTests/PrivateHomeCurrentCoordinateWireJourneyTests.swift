import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Original service/coordinator with synthetic wire and journal only.
/// No claim is made about a particular Foundation version's rounding of hostile tokens.
@available(macOS 14.0, *) @MainActor final class PrivateHomeCurrentCoordinateWireJourneyTests: XCTestCase {
    private static func snapshot(_ latitude: String = "12.123456", _ longitude: String = "45.654321", version: Int64 = 3) -> String {
        "{\"version\":\(version),\"status\":\"ACTIVE\",\"label\":\"Synthetic\",\"latitude\":\(latitude),\"longitude\":\(longitude),\"datum\":\"WGS84\",\"changedAt\":1,\"effectiveAt\":1}"
    }
    private static func envelope(_ data: String, code: Int = 200) -> Data { Data("{\"code\":\(code),\"data\":\(data)}".utf8) }
    @MainActor private final class Wire: HTTPTransport {
        var get = PrivateHomeCurrentCoordinateWireJourneyTests.envelope(PrivateHomeCurrentCoordinateWireJourneyTests.snapshot())
        var status = 200
        var requests: [URLRequest] = []
        var loseWrite = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.httpMethod == "GET" { return (get, status) }
            if loseWrite { throw PrivateHomeIssue.unknownOutcome }
            let mutation = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(request.httpBody))
            let decision = mutation.method == "PUT" ? "SAVED" : "DELETED"
            return (PrivateHomeCurrentCoordinateWireJourneyTests.envelope("{\"requestId\":\"\(mutation.requestId)\",\"decision\":\"\(decision)\",\"version\":\(mutation.expectedVersion + 1)}"), 200)
        }
        var writes: [URLRequest] { requests.filter { $0.httpMethod != "GET" } }
    }
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() -> PrivateHomeMutation? { value }
        func save(_ mutation: PrivateHomeMutation) throws {
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = mutation; saves += 1
        }
        func clear(matching mutation: PrivateHomeMutation) throws {
            guard value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = nil; clears += 1
        }
    }
    @MainActor private final class Identity {
        var current: PlayExperienceSession?
        init(_ owner: PlayExperienceSession) { current = owner }
    }
    @MainActor private final class Fixture {
        let owner: PlayExperienceSession, identity: Identity, wire: Wire, journal: Journal
        let service: PrivateHomeService
        init(enabled: Bool = true) throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-current-point", token: "synthetic-token")
            let identity = Identity(owner), wire = Wire()
            self.owner = owner; self.identity = identity; self.wire = wire; journal = Journal(owner)
            service = PrivateHomeService(api: try APIConfiguration(baseURL: URL(string: "https://point-read.example.test")!),
                transport: wire, owner: owner, enabled: enabled, current: { identity.current })
        }
        func model() -> PrivateHomeCoordinator {
            .init(service: service, journal: journal, owner: owner, enabled: true, current: { self.identity.current })
        }
    }
    private func reject(_ snapshot: String) async throws {
        let f = try Fixture(); f.wire.get = Self.envelope(snapshot)
        do { _ = try await f.service.load(); XCTFail("Original out-of-contract point must not be accepted") }
        catch { XCTAssertEqual(error as? PrivateHomeIssue, .invalid) }
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertTrue(f.wire.writes.isEmpty)
    }

    func testAllExactCoordinateExtremesAndSixPlaceValuesRemainValid() async throws {
        for pair in [("90", "180"), ("-90", "-180"), ("0", "-0"),
                     ("89.999999", "179.999999"), ("-89.999999", "-179.999999"), ("0.000001", "-0.000001")] {
            let f = try Fixture(); f.wire.get = Self.envelope(Self.snapshot(pair.0, pair.1))
            let value = try await f.service.load(); try value.validate()
            XCTAssertEqual(value.latitude, Decimal(string: pair.0, locale: Locale(identifier: "en_US_POSIX")))
            XCTAssertEqual(value.longitude, Decimal(string: pair.1, locale: Locale(identifier: "en_US_POSIX")))
        }
    }
    func testLegalExponentTrailingZerosAndNegativeZeroRemainCompatible() async throws {
        for pair in [("12.1234560000", "45.6543210000"), ("90000000e-6", "-180000000e-6"),
                     ("120000000000e-10", "45e0"), ("123456e-6", "-123456e-6"), ("-0.0000000", "0e-6")] {
            let f = try Fixture(); f.wire.get = Self.envelope(Self.snapshot(pair.0, pair.1))
            let value = try await f.service.load(); try value.validate()
        }
    }
    func testNonzeroTailsBeyondDecimalPrecisionCannotRoundIntoValidPoint() async throws {
        for token in ["12.00000000000000000000000000000000000000001", "-12.00000000000000000000000000000000000000001",
                      "0.00000000000000000000000000000000000000001", "-0.00000000000000000000000000000000000000001",
                      "12345678901234567890123456789012345678901e-40"] {
            try await reject(Self.snapshot(token, "45")); try await reject(Self.snapshot("12", token))
        }
    }
    func testLongTailsOutsideBothSignedBoundsCannotRoundBackToBoundary() async throws {
        for token in ["90.00000000000000000000000000000000000000001", "-90.00000000000000000000000000000000000000001"] {
            try await reject(Self.snapshot(token, "45"))
        }
        for token in ["180.00000000000000000000000000000000000000001", "-180.00000000000000000000000000000000000000001"] {
            try await reject(Self.snapshot("12", token))
        }
    }
    func testOrdinaryInvalidScaleRangeAndExponentRemainRejected() async throws {
        for token in ["12.1234567", "1e-7", "-1e-7", "1e1000", "-1e1000", "1e-1000", "91", "-91", "90.000001", "-90.000001"] {
            try await reject(Self.snapshot(token, "45"))
        }
        for token in ["181", "-181", "180.000001", "-180.000001"] { try await reject(Self.snapshot("12", token)) }
    }
    func testActiveCoordinatesMustBeActualJsonNumbers() async throws {
        for token in [#""12""#, "true", "false", "null", "{}", "[]"] {
            try await reject(Self.snapshot(token, "45")); try await reject(Self.snapshot("12", token))
        }
        try await reject(Self.snapshot().replacingOccurrences(of: #""latitude":12.123456,"#, with: ""))
        try await reject(Self.snapshot().replacingOccurrences(of: #""longitude":45.654321,"#, with: ""))
    }
    func testEscapedKeysWhitespaceAndUnknownExtensionNumbersAreUnaffected() async throws {
        let f = try Fixture()
        let original = Self.snapshot().replacingOccurrences(of: "latitude", with: "\\u006catitude")
        let withExtension = String(original.dropLast()) + #", "future":{"number":12.00000000000000000000000000000000000000001}}"#
        f.wire.get = Data(" \n".utf8) + Self.envelope(withExtension) + Data("\n ".utf8)
        let value = try await f.service.load(); XCTAssertEqual(value.latitude, Decimal(string: "12.123456"))
        let invalid = withExtension.replacingOccurrences(of: "12.123456,", with: "12.1234567,")
        try await reject(invalid)
    }
    func testDeletedSnapshotsDoNotAcquireAnActiveCoordinateRequirement() async throws {
        let f = try Fixture()
        for snapshot in [#"{"version":0,"status":"DELETED"}"#,
                         #"{"version":4,"status":"DELETED","label":null,"latitude":null,"longitude":null,"datum":null,"changedAt":null,"effectiveAt":null}"#] {
            f.wire.get = Self.envelope(snapshot); let home = try await f.service.load()
            XCTAssertEqual(home.status, .deleted); XCTAssertNil(home.latitude); XCTAssertNil(home.longitude)
        }
    }
    func testNonSuccessResponsesKeepOriginalUnavailableSemantics() async throws {
        let f = try Fixture(), invalidPoint = Self.snapshot("12.1234567", "45")
        f.wire.get = Self.envelope(invalidPoint, code: 409)
        do { _ = try await f.service.load(); XCTFail() } catch { XCTAssertEqual(error as? PrivateHomeIssue, .unavailable) }
        f.wire.get = Self.envelope(invalidPoint); f.wire.status = 503
        do { _ = try await f.service.load(); XCTFail() } catch { XCTAssertEqual(error as? PrivateHomeIssue, .unavailable) }
    }
    func testInvalidFirstCurrentReadCannotEnableReviewAndManualValidRefreshCan() async throws {
        let f = try Fixture(), model = f.model()
        f.wire.get = Self.envelope(Self.snapshot("12.00000000000000000000000000000000000000001", "45"))
        await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit)
        model.prepareSet(label: "Must not stage", point: try .init(latitude: 12, longitude: 45)); await model.confirm()
        XCTAssertNil(model.review); XCTAssertTrue(f.wire.writes.isEmpty); XCTAssertEqual(f.journal.saves, 0)
        f.wire.get = Self.envelope(Self.snapshot()); await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canEdit); XCTAssertTrue(f.wire.writes.isEmpty)
    }
    func testInvalidReadCannotAdvanceCurrentVersionFloorOrUnlockKnownUnknown() async throws {
        let f = try Fixture(), model = f.model(); await model.load()
        f.wire.get = Self.envelope(Self.snapshot("12.00000000000000000000000000000000000000001", "45", version: 999))
        await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit)
        f.wire.get = Self.envelope(Self.snapshot(version: 4)); await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.home?.version, 4)
        let original = try PrivateHomeMutation(requestId: "original-pending", expectedVersion: 4)
        f.journal.value = original
        f.wire.get = Self.envelope(Self.snapshot("12.00000000000000000000000000000000000000001", "45", version: 1_000))
        await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertFalse(model.canEdit); XCTAssertEqual(f.journal.value, original)
        XCTAssertEqual(f.journal.clears, 0); XCTAssertTrue(f.wire.writes.isEmpty)
    }
    func testLostOriginalWriteAndMalformedCurrentReadRetainUnknownUntilExplicitRetry() async throws {
        let f = try Fixture(), model = f.model(); await model.load()
        model.prepareSet(label: "Synthetic", point: try .init(latitude: 12, longitude: 45))
        let original = try XCTUnwrap(model.review); f.wire.loseWrite = true; await model.confirm()
        XCTAssertEqual(model.phase, .unknown)
        f.wire.get = Self.envelope(Self.snapshot("12.00000000000000000000000000000000000000001", "45", version: 4))
        await model.load(); XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(f.journal.value, original)
        XCTAssertEqual(f.wire.writes.count, 1); XCTAssertEqual(f.journal.clears, 0)
        f.wire.loseWrite = false; await model.retryExact()
        XCTAssertEqual(f.wire.writes.count, 2); XCTAssertEqual(f.wire.writes[0].httpBody, f.wire.writes[1].httpBody)
        XCTAssertEqual(model.decision, .saved); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit)
        f.wire.get = Self.envelope(Self.snapshot(version: 4)); await model.load()
        XCTAssertTrue(model.canEdit); XCTAssertEqual(model.decision, .saved); XCTAssertEqual(f.wire.writes.count, 2)
    }
    func testPutAndDeleteReceiptsRemainValidWithoutCoordinateFields() async throws {
        let f = try Fixture()
        for mutation in [try PrivateHomeMutation(requestId: "original-put", expectedVersion: 3, label: "Synthetic", point: .init(latitude: 12, longitude: 45)),
                         try PrivateHomeMutation(requestId: "original-delete", expectedVersion: 4)] {
            let receipt = try await f.service.mutate(mutation); try receipt.validate(for: mutation)
            XCTAssertEqual(receipt.version, mutation.expectedVersion + 1)
        }
        XCTAssertEqual(f.wire.requests.compactMap(\.httpMethod), ["PUT", "DELETE"])
    }
    func testDefaultOffAndStaleOwnerStillStopBeforeAnyTransport() async throws {
        let disabled = try Fixture(enabled: false)
        do { _ = try await disabled.service.load(); XCTFail() } catch { XCTAssertEqual(error as? PrivateHomeIssue, .disabled) }
        XCTAssertTrue(disabled.wire.requests.isEmpty)
        let stale = try Fixture(); stale.identity.current = nil
        do { _ = try await stale.service.load(); XCTFail() } catch { XCTAssertEqual(error as? PrivateHomeIssue, .staleSession) }
        XCTAssertTrue(stale.wire.requests.isEmpty)
    }
}

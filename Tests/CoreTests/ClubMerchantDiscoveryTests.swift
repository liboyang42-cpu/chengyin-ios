import XCTest
import Observation
@testable import QuestifyCore

final class ClubMerchantKeywordTests: XCTestCase {
    private func row(_ fields: [String: CoopFlowJSON], _ index: Int = 0) throws -> ClubMerchantDiscoveryRow {
        try .init(value: .object(fields), index: index)
    }
    func testEverySourceFieldMatchesWithoutReorderingOrDeduplication() throws {
        let keys = ["name", "merchantName", "suitActivityTypes", "address", "city"]
        let rows = try keys.enumerated().map { try row([$0.element: .string("ALPHA 城市")], $0.offset) }
        XCTAssertEqual(ClubMerchantKeyword(" alpha ").filter(rows).map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(ClubMerchantKeyword("城市").filter(rows), rows)
        XCTAssertEqual(ClubMerchantKeyword("").filter(rows + rows), rows + rows)
        XCTAssertTrue(ClubMerchantKeyword("missing").filter(rows).isEmpty)
    }
    func testSourceJoinsFieldsWithExactlyOneSpaceAndPreservesInteriorWhitespace() throws {
        let rows = [try row(["name": .string("First"), "merchantName": .string("Second"), "address": .string("Two  Spaces")])]
        XCTAssertEqual(ClubMerchantKeyword("first second").filter(rows), rows)
        XCTAssertEqual(ClubMerchantKeyword("second  two").filter(rows), rows)
        XCTAssertTrue(ClubMerchantKeyword("two spaces").filter(rows).isEmpty)
    }
    func testECMAScriptTrimIncludesBOMButExcludesNELAndZeroWidthSpace() throws {
        let rows = [try row(["name": .string("Cafe")])]
        let whitespace = "\u{0009}\u{000B}\u{000C}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}\u{FEFF}\u{000A}\u{000D}\u{2028}\u{2029}"
        XCTAssertEqual(ClubMerchantKeyword(whitespace + "CAFE" + whitespace).filter(rows), rows)
        XCTAssertEqual(ClubMerchantKeyword(whitespace).filter(rows), rows)
        XCTAssertTrue(ClubMerchantKeyword("\u{0085}Cafe").filter(rows).isEmpty)
        XCTAssertTrue(ClubMerchantKeyword("\u{200B}Cafe").filter(rows).isEmpty)
    }
    func testUTF16SubstringDoesNotFoldCanonicalEquivalenceOrGraphemeBoundaries() throws {
        let decomposed = try row(["name": .string("Cafe\u{0301} 👩‍🚀")])
        let rows = [decomposed]
        XCTAssertTrue(ClubMerchantKeyword("Café").filter(rows).isEmpty)
        XCTAssertEqual(ClubMerchantKeyword("\u{0301}").filter(rows), rows)
        XCTAssertEqual(ClubMerchantKeyword("🚀").filter(rows), rows)
        XCTAssertEqual(ClubMerchantKeyword("👩").filter(rows), rows)
    }
    func testLowercaseDoesNotUseCaseOrDiacriticFolding() throws {
        let rows = [try row(["name": .string("Straße İSTANBUL")])]
        XCTAssertTrue(ClubMerchantKeyword("STRASSE").filter(rows).isEmpty)
        XCTAssertEqual(ClubMerchantKeyword("straße").filter(rows), rows)
        XCTAssertEqual(ClubMerchantKeyword("i\u{0307}stanbul").filter(rows), rows)
        XCTAssertTrue(ClubMerchantKeyword("istanbul").filter(rows).isEmpty)
    }
    func testMissingNullableFieldsStayEmptyAndUnrelatedMetadataDoesNotMatch() throws {
        let value = try row(["name": .null, "merchantName": .string("Alternate"), "description": .string("Secret")])
        XCTAssertEqual(value.name, "Alternate"); XCTAssertEqual(value.fields.count, 5)
        XCTAssertTrue(ClubMerchantKeyword("secret").filter([value]).isEmpty)
        XCTAssertEqual(ClubMerchantKeyword("").filter([try row([:])]).count, 1)
    }
    func testMalformedFieldsAndNonObjectsFailInsteadOfBecomingEmptyResults() throws {
        let values: [CoopFlowJSON] = [.null, .array([]), .string("bad"), .object(["city": .bool(true)]), .object(["suitActivityTypes": .array([])])]
        for value in values {
            XCTAssertThrowsError(try ClubMerchantDiscoveryRow(value: value, index: 0))
        }
    }
    func testReadContractKeepsEmptyJSONAndExistingPath() throws {
        XCTAssertEqual(CoopFlowRead.merchants(name: nil).path, "api/club/merchants")
        XCTAssertEqual(try CoopFlowRead.merchants(name: nil).body(), .object([:]))
    }
}

@MainActor final class ClubMerchantDiscoveryModelTests: XCTestCase {
    private func context(_ club: MerchantDiscoveryClubReader, _ reader: any CoopFlowReading, owner: Bool = true, id: Int = 9) -> ClubMerchantDiscoveryContext {
        .init(club: MerchantDiscoveryClubReader.record(owner: owner, id: id), clubReader: club, reader: reader)
    }
    private func activate(_ model: ClubMerchantDiscoveryModel, _ context: ClubMerchantDiscoveryContext) throws -> ClubMerchantDiscoveryModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    func testPreActivationPhaseObservationNotifiesTheFirstRenderedScreen() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let scope = context(club, reader), changed = expectation(description: "First screen observes phase changes")
        model.bind(scope)
        withObservationTracking { _ = model.phase(in: scope) } onChange: { changed.fulfill() }
        let permit = try XCTUnwrap(model.activate(scope))
        await model.load(clubReader: club, reader: reader, permit: permit)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(model.phase(in: scope), .ready)
    }
    func testOwnerReadThenDirectoryOnceAndKeywordsNeverDispatch() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let scope = context(club, reader), permit = try activate(model, context(club, reader))
        await model.load(clubReader: club, reader: reader, permit: permit)
        XCTAssertEqual(club.reads, 1); XCTAssertEqual(reader.resources, [.merchants(name: nil)])
        model.setKeyword("ALPHA", permit: permit)
        XCTAssertEqual(model.rows(in: scope).map(\.name), ["Alpha"])
        model.setKeyword("missing", permit: permit)
        XCTAssertTrue(model.rows(in: scope).isEmpty); XCTAssertTrue(model.hasLoadedRows(in: scope))
        model.setKeyword("", permit: permit)
        XCTAssertEqual(model.rows(in: scope).count, 2); XCTAssertEqual(reader.resources.count, 1)
    }
    func testGuestNonOwnerAndMismatchedSessionsCannotActivateOrRead() throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        var scopes = [context(club, reader, owner: false)]
        reader.session = nil; scopes.append(context(club, reader))
        reader.session = try .init(accountID: 2, epoch: 1, token: "synthetic"); scopes.append(context(club, reader))
        reader.session = try .init(accountID: 1, epoch: 2, token: "synthetic"); scopes.append(context(club, reader))
        club.isClubConfigured = false; scopes.append(context(club, reader))
        for scope in scopes { model.bind(scope); XCTAssertFalse(scope.canRead); XCTAssertNil(model.activate(scope)) }
        XCTAssertEqual(club.reads, 0); XCTAssertTrue(reader.resources.isEmpty)
    }
    func testFreshOwnerLossOrWrongClubPreventsDirectoryRead() async throws {
        for returned in [MerchantDiscoveryClubReader.record(owner: false), MerchantDiscoveryClubReader.record(id: 10)] {
            let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
            club.returned = returned
            let scope = context(club, reader), permit = try activate(model, context(club, reader))
            await model.load(clubReader: club, reader: reader, permit: permit)
            XCTAssertEqual(model.phase(in: scope), .denied); XCTAssertTrue(reader.resources.isEmpty)
        }
    }
    func testEmptyAndMalformedDirectoryAndFailureAreDistinct() async throws {
        let cases: [(CoopFlowJSON, ClubMerchantDiscoveryModel.Phase)] = [(.array([]), .ready), (.object([:]), .failed), (.array([.null]), .failed)]
        for (value, phase) in cases {
            let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
            reader.value = value
            let scope = context(club, reader), permit = try activate(model, context(club, reader))
            await model.load(clubReader: club, reader: reader, permit: permit)
            XCTAssertEqual(model.phase(in: scope), phase); XCTAssertFalse(model.hasLoadedRows(in: scope))
        }
    }
    func testNewOwnerContextImmediatelyHidesRowsAndRejectsOldInput() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let old = context(club, reader), permit = try activate(model, old)
        await model.load(clubReader: club, reader: reader, permit: permit)
        let replacement = context(club, reader, owner: false)
        model.bind(replacement)
        XCTAssertTrue(model.rows(in: old).isEmpty); XCTAssertTrue(model.rows(in: replacement).isEmpty)
        model.setKeyword("late", permit: permit)
        await model.load(clubReader: club, reader: reader, permit: permit)
        XCTAssertEqual(reader.resources.count, 1); XCTAssertEqual(model.keyword(in: replacement), "")
    }
    func testLeaveReappearRejectsOldRetryAndKeyboardCallbacks() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let scope = context(club, reader), old = try activate(model, context(club, reader))
        await model.load(clubReader: club, reader: reader, permit: old)
        model.setKeyword("old", permit: old); model.leave(scope)
        let current = try XCTUnwrap(model.activate(scope))
        XCTAssertNotEqual(old, current)
        model.setKeyword("new", permit: current); model.setKeyword("late", permit: old)
        await model.load(clubReader: club, reader: reader, permit: old)
        XCTAssertEqual(model.keyword(in: scope), "new"); XCTAssertEqual(reader.resources.count, 1)
    }
    func testLateSuccessOrFailureAfterLeaveCannotPublish() async throws {
        for fail in [false, true] {
            let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
            reader.hold = true
            let started = expectation(description: "directory dispatched"); reader.onRead = { _ in started.fulfill() }
            let scope = context(club, reader), permit = try activate(model, context(club, reader))
            let task = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
            await fulfillment(of: [started], timeout: 2)
            model.leave(scope); reader.finish(1, fail: fail); await task.value
            XCTAssertEqual(model.phase(in: scope), .idle); XCTAssertTrue(model.rows(in: scope).isEmpty)
        }
    }
    func testNewerRefreshWinsOverLateOldReplyAndFailure() async throws {
        for fail in [false, true] {
            let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
            reader.hold = true
            let first = expectation(description: "old"), second = expectation(description: "new")
            reader.onRead = { if $0 == 1 { first.fulfill() } else { second.fulfill() } }
            let scope = context(club, reader), permit = try activate(model, context(club, reader))
            let old = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
            await fulfillment(of: [first], timeout: 2)
            let new = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
            await fulfillment(of: [second], timeout: 2)
            reader.finish(1, fail: fail); await old.value
            XCTAssertEqual(model.phase(in: scope), .loading)
            reader.finish(2); await new.value
            XCTAssertEqual(model.phase(in: scope), .ready); XCTAssertEqual(model.rows(in: scope).count, 2)
        }
    }
    func testReaderReplacementFencesPendingSuccessBeforeReplacementTask() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), replacement = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        reader.hold = true
        let started = expectation(description: "old reader"); reader.onRead = { _ in started.fulfill() }
        let scope = context(club, reader), permit = try activate(model, context(club, reader))
        let task = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
        await fulfillment(of: [started], timeout: 2)
        let newScope = context(club, replacement); model.bind(newScope)
        reader.finish(1); await task.value
        XCTAssertTrue(model.rows(in: scope).isEmpty); XCTAssertEqual(model.phase(in: newScope), .idle)
        await model.load(clubReader: club, reader: replacement, permit: permit)
        XCTAssertTrue(replacement.resources.isEmpty)
    }
    func testSessionEpochChangeAndCancellationRejectLateReplyAndClearOwnLoading() async throws {
        for cancel in [false, true] {
            let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
            reader.hold = true
            let started = expectation(description: "pending"); reader.onRead = { _ in started.fulfill() }
            let scope = context(club, reader), permit = try activate(model, context(club, reader))
            let task = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
            await fulfillment(of: [started], timeout: 2)
            if cancel { task.cancel() } else { reader.session = try .init(accountID: 1, epoch: 2, token: "synthetic-new") }
            reader.finish(1); await task.value
            XCTAssertTrue(model.rows(in: scope).isEmpty); XCTAssertEqual(model.phase(in: scope), .idle)
        }
    }
    func testOldUnauthorizedCannotExpireSessionAfterOwnerOrReaderChanges() async throws {
        for ownerLoss in [false, true] {
            let wire = MerchantDiscoveryHeldWire(), club = MerchantDiscoveryClubReader(), model = ClubMerchantDiscoveryModel()
            let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "synthetic")
            var expirations = 0
            let reader = CoopFlowSessionReader(service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire), current: { session }, unauthorized: { _ in expirations += 1 })
            let scope = context(club, reader), permit = try activate(model, context(club, reader))
            let task = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
            await wire.waitUntilRead()
            if ownerLoss { model.bind(context(club, reader, owner: false)) }
            else { model.bind(context(club, MerchantDiscoveryDirectoryReader())) }
            await wire.finishUnauthorized(); await task.value
            XCTAssertEqual(expirations, 0); XCTAssertTrue(model.rows(in: scope).isEmpty)
        }
    }
    func testOldClubOwnerReadCannotExpireSessionOrDispatchAfterContextReplacement() async throws {
        let wire = MerchantDiscoveryHeldWire(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let session = try ClubReadSession(accountID: 1, epoch: 1, token: "synthetic")
        var expirations = 0
        let club = ClubSessionReader(service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire), currentSession: { session }, onUnauthorized: { _ in expirations += 1 })
        let scope = ClubMerchantDiscoveryContext(club: MerchantDiscoveryClubReader.record(), clubReader: club, reader: reader)
        let permit = try activate(model, scope)
        let task = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
        await wire.waitUntilRead()
        model.bind(context(MerchantDiscoveryClubReader(), reader))
        await wire.finishUnauthorized(); await task.value
        XCTAssertEqual(expirations, 0); XCTAssertTrue(reader.resources.isEmpty); XCTAssertTrue(model.rows(in: scope).isEmpty)
    }
    func testLeavingDuringFreshOwnerReadPreventsDirectoryDispatchEvenOnLateSuccess() async throws {
        let wire = MerchantDiscoveryHeldWire(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let session = try ClubReadSession(accountID: 1, epoch: 1, token: "synthetic")
        let club = ClubSessionReader(service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire), currentSession: { session })
        let scope = ClubMerchantDiscoveryContext(club: MerchantDiscoveryClubReader.record(), clubReader: club, reader: reader)
        let permit = try activate(model, scope)
        let task = Task { await model.load(clubReader: club, reader: reader, permit: permit) }
        await wire.waitUntilRead()
        model.leave(scope); await wire.finishOwner(); await task.value
        XCTAssertTrue(reader.resources.isEmpty); XCTAssertEqual(model.phase(in: scope), .idle)
    }
    func testAlreadyCancelledCallbackCannotClearAcceptedSnapshot() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let scope = context(club, reader), permit = try activate(model, context(club, reader))
        await model.load(clubReader: club, reader: reader, permit: permit)
        let gate = MerchantDiscoveryTaskGate()
        let old = Task { await gate.wait(); await model.load(clubReader: club, reader: reader, permit: permit) }
        old.cancel(); gate.open(); await old.value
        XCTAssertEqual(reader.resources.count, 1); XCTAssertEqual(model.phase(in: scope), .ready)
        XCTAssertEqual(model.rows(in: scope).count, 2)
    }
    func testRefreshRetainsQueryWhileReplacementVisibilityClearsIt() async throws {
        let club = MerchantDiscoveryClubReader(), reader = MerchantDiscoveryDirectoryReader(), model = ClubMerchantDiscoveryModel()
        let scope = context(club, reader), permit = try activate(model, context(club, reader))
        model.setKeyword("beta", permit: permit)
        await model.load(clubReader: club, reader: reader, permit: permit)
        await model.load(clubReader: club, reader: reader, permit: permit)
        XCTAssertEqual(model.rows(in: scope).map(\.name), ["Beta"])
        XCTAssertEqual(model.keyword(in: scope), "beta")
        model.leave(scope); _ = model.activate(scope)
        XCTAssertEqual(model.keyword(in: scope), "")
    }
}

@MainActor private final class MerchantDiscoveryClubReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var reads = 0
    var returned = MerchantDiscoveryClubReader.record()
    static func record(owner: Bool = true, id: Int = 9) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return returned }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class MerchantDiscoveryDirectoryReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID: 1, epoch: 1, token: "synthetic")
    var value: CoopFlowJSON = .array([.object(["name": .string("Alpha")]), .object(["name": .string("Beta")])])
    var resources: [CoopFlowRead] = []
    var hold = false
    var onRead: ((Int) -> Void)?
    private var pending: [Int: CheckedContinuation<CoopFlowJSON, Error>] = [:]
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        resources.append(resource); let id = resources.count
        if !hold { onRead?(id); return value }
        return try await withCheckedThrowingContinuation { pending[id] = $0; onRead?(id) }
    }
    func finish(_ id: Int, fail: Bool = false) {
        if fail { pending.removeValue(forKey: id)?.resume(throwing: APIError.unauthorized) }
        else { pending.removeValue(forKey: id)?.resume(returning: value) }
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
private actor MerchantDiscoveryHeldWire: HTTPTransport {
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await withCheckedThrowingContinuation { pending = $0 } }
    func waitUntilRead() async { while pending == nil { await Task.yield() } }
    func finishUnauthorized() { pending?.resume(returning: (Data(#"{"code":401}"#.utf8), 401)); pending = nil }
    func finishOwner() { pending?.resume(returning: (Data(#"{"code":200,"data":{"id":9,"isOwner":true}}"#.utf8), 200)); pending = nil }
}
@MainActor private final class MerchantDiscoveryTaskGate {
    private var opened = false
    private var waiting: CheckedContinuation<Void, Never>?
    func wait() async { if opened { return }; await withCheckedContinuation { waiting = $0 } }
    func open() { opened = true; let old = waiting; waiting = nil; old?.resume() }
}

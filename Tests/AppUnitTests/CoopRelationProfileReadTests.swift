import XCTest
import Combine
@testable import Questify

#if DEBUG
@MainActor final class CoopRelationFixtureReadLedgerTests: XCTestCase {
    func testRealReadAccountingDoesNotRepublishTheNavigationIdentityOwner() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed")
        var ownerPublications = 0, counterPublications = 0
        let identityObservation = reader.objectWillChange.sink { ownerPublications += 1 }
        let counterObservation = reader.ledger.objectWillChange.sink { counterPublications += 1 }
        _ = try await reader.read(.relations)
        _ = try await reader.home(.ownerMemberID(PublicMerchantOwnerID(41)!))
        _ = try await reader.clubDetail(id: 9)
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(reader.ownerReads, 1); XCTAssertEqual(reader.clubReads, 1)
        XCTAssertEqual(ownerPublications, 0, "Fixture bookkeeping must not rebuild the environment owner during a profile read")
        XCTAssertEqual(counterPublications, 3)
        withExtendedLifetime((identityObservation, counterObservation)) {}
    }
    func testIdentityReplacementStillPublishesAndRejectsTheOldScopedProfile() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), scope = reader.scope, session = reader.session
        let profile = CoopRelationMerchantReader(base: reader, owner: PublicMerchantOwnerID(41)!, isCurrent: { reader.scope == scope && reader.session == session })
        _ = try await profile.home(.ownerMemberID(PublicMerchantOwnerID(41)!))
        var publications = 0
        let observation = reader.objectWillChange.sink { publications += 1 }
        reader.session = try .init(accountID: 102, epoch: 2, token: "replacement")
        reader.scope = UUID()
        XCTAssertEqual(publications, 2); XCTAssertFalse(profile.isConfigured)
        do { _ = try await profile.home(.ownerMemberID(PublicMerchantOwnerID(41)!)); XCTFail("Old selection dispatched after identity replacement") } catch {}
        XCTAssertEqual(reader.ownerReads, 1)
        withExtendedLifetime(observation) {}
    }
    func testAcceptedClubChoiceStaysCurrentDuringItsOwnLedgerPublication() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), model = CoopRelationDiscoveryModel()
        let scope = CoopRelationProfileScope(merchantScope: reader.scope, clubIdentity: reader.clubIdentity, sessionRevision: 1, contentRevision: 1)
        let context = CoopRelationDisplayContext(topicID: 3, chapterID: 5)
        await model.load(reader: reader)
        let choice = try XCTUnwrap(model.selection(row: try XCTUnwrap(model.value?.clubs.first), reader: reader, scope: scope, context: context))
        model.leaveScreen()
        let profile = CoopRelationClubProfileReader(base: reader, clubID: 9, isCurrent: { model.isCurrent(choice, reader: reader, scope: scope, context: context) })
        var publications = 0
        let observation = reader.objectWillChange.sink { publications += 1 }
        let value = try await profile.clubDetail(id: 9)
        XCTAssertEqual(value.id, 9); XCTAssertEqual(reader.clubReads, 1); XCTAssertEqual(reader.reads, 1)
        XCTAssertEqual(publications, 0); XCTAssertTrue(profile.isClubConfigured)
        XCTAssertTrue(model.isCurrent(choice, reader: reader, scope: scope, context: context))
        await model.load(reader: reader)
        XCTAssertFalse(profile.isClubConfigured, "Explicit refresh still retires the previous accepted snapshot")
        withExtendedLifetime(observation) {}
    }
    func testCountersRemainMonotonicAcrossSyntheticIdentityChangesAndFailures() async throws {
        let reader = CoopRelationFixtureReader(scenario: "retry"), ledger = reader.ledger
        do { _ = try await reader.read(.relations); XCTFail("Expected the original first-read fixture failure") } catch {}
        _ = try await reader.read(.relations)
        _ = try await reader.home(.ownerMemberID(PublicMerchantOwnerID(41)!))
        reader.session = nil; reader.scope = UUID()
        XCTAssertTrue(reader.ledger === ledger)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(reader.ownerReads, 1); XCTAssertEqual(reader.clubReads, 0)
    }
}

#endif

@MainActor final class CoopRelationProfileReadTests: XCTestCase {
    func testMerchantAdapterRejectsRowNamespaceBeforeAnyRead() async throws {
        let base = RelationMerchantBase(), owner = PublicMerchantOwnerID(41)!
        let reader = CoopRelationMerchantReader(base: base, owner: owner, isCurrent: { true })
        do { _ = try await reader.home(.legacyMerchantRowID(PublicMerchantRowID(41)!)); XCTFail() } catch { }
        do { _ = try await reader.home(.ownerMemberID(PublicMerchantOwnerID(8)!)); XCTFail() } catch { }
        XCTAssertEqual(base.reads, 0)
        let home = try await reader.home(.ownerMemberID(owner))
        XCTAssertEqual(home.memberId, 41); XCTAssertEqual(base.reads, 1)
    }
    func testMerchantAdapterRejectsMissingMismatchedAndStaleReturnedIdentity() async throws {
        let owner = PublicMerchantOwnerID(41)!
        for json in [#"{"id":8,"memberId":8}"#, #"{"id":8}"#, #"{"memberId":41}"#, #"{"id":0,"memberId":41}"#] {
            let base = RelationMerchantBase(); base.json = json
            let reader = CoopRelationMerchantReader(base: base, owner: owner, isCurrent: { true })
            do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail("Unverified owner accepted") } catch { }
        }
        let base = RelationMerchantBase(); var current = true
        base.hook = { current = false }
        let reader = CoopRelationMerchantReader(base: base, owner: owner, isCurrent: { current })
        do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail() } catch { }
        XCTAssertFalse(reader.isConfigured)
    }
    func testClubAdapterAllowsOnlySelectedReadAndRejectsStaleReadback() async throws {
        let base = RelationClubBase(); var current = true
        let reader = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { current })
        do { _ = try await reader.clubDetail(id: 41); XCTFail() } catch { }
        do { _ = try await reader.clubHome(); XCTFail() } catch { }
        XCTAssertEqual(base.reads, 0)
        let club = try await reader.clubDetail(id: 9)
        XCTAssertEqual(club.id, 9)
        base.hook = { current = false }
        do { _ = try await reader.clubDetail(id: 9); XCTFail() } catch { }
        XCTAssertFalse(reader.isClubConfigured)
    }
    func testOlderClubRefreshUnauthorizedCannotExpireNewerSuccessfulRead() async throws {
        let wire = RelationSuspendedWire()
        let session = try ClubReadSession(accountID: 1, epoch: 1, token: "same")
        var expired = 0
        let service = ClubService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let base = ClubSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        let reader = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { true })
        let old = Task { try await reader.clubDetail(id: 9) }
        await wire.waitForFirst()
        let newer = try await reader.clubDetail(id: 9)
        XCTAssertEqual(newer.id, 9)
        await wire.finishOldUnauthorized()
        do { _ = try await old.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    func testClubAdapterRejectsWrongReturnedClub() async throws {
        let base = RelationClubBase(); base.returnedID = 41
        let reader = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { true })
        do { _ = try await reader.clubDetail(id: 9); XCTFail() } catch { }
    }
}
@MainActor private final class RelationMerchantBase: PublicMerchantHomeReading {
    let scope = UUID(), isConfigured = true, isOfflineExample = true
    var reads = 0
    var json = #"{"id":8,"memberId":41}"#
    var hook: (() -> Void)?
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        reads += 1; hook?()
        return try JSONDecoder().decode(PublicMerchantHome.self, from: Data(json.utf8))
    }
}
@MainActor private final class RelationClubBase: ClubReading {
    let isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var returnedID = 9
    var reads = 0
    var hook: (() -> Void)?
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1; hook?()
        return try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(returnedID)}".utf8))
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}

private actor RelationSuspendedWire: HTTPTransport {
    private var count = 0
    private var first: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        count += 1
        if count == 1 { return try await withCheckedThrowingContinuation { first = $0 } }
        return (Data(#"{"code":200,"data":{"id":9}}"#.utf8), 200)
    }
    func waitForFirst() async { while first == nil { await Task.yield() } }
    func finishOldUnauthorized() { first?.resume(returning: (Data(#"{"code":401}"#.utf8), 401)); first = nil }
}

@MainActor final class CooperationPhoneCopyOwnerTests: XCTestCase {
    @MainActor private final class Reader: CooperationReading {
        var scope = UUID(), isConfigured = true, isAuthenticated = true
        let isOfflineExample = true
        var reads = 0
        var value: CooperationInviteDetail
        var suspendNext = false
        var continuation: CheckedContinuation<CooperationInviteDetail, Error>?
        init(phone: String? = "  +1 202 555 0100  ") throws {
            var fields: [String: Any] = ["id": 71, "partner": ["name": "Synthetic partner"]]
            if let phone { fields["partner"] = ["name": "Synthetic partner", "phone": phone] }
            let row = try JSONDecoder().decode(CooperationInvite.self, from: JSONSerialization.data(withJSONObject: fields))
            value = .init(row: row, occupancy: nil)
        }
        func detail(key: CooperationInviteKey) async throws -> CooperationInviteDetail {
            reads += 1
            if suspendNext {
                suspendNext = false
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
            return value
        }
        func inbox(direction: CooperationDirection) async throws -> CooperationInbox { throw APIError.invalidRequest }
        func pool() async throws -> CooperationPool { throw APIError.invalidRequest }
        func candidates(topicID: Int) async throws -> CooperationCandidates { throw APIError.invalidRequest }
    }
    private let key = CooperationInviteKey(id: 71, direction: .received)
    private func loaded(_ reader: Reader) async throws -> (CooperationPhoneCopyOwner, CooperationInviteDetail) {
        let owner = CooperationPhoneCopyOwner(reader: reader, key: key)
        owner.appear(active: true)
        return (owner, try await owner.load(reader: reader, key: key))
    }
    func testExplicitGestureCopiesOnlyExactReturnedPhoneOnceAndReportsResult() async throws {
        let reader = try Reader(), (owner, detail) = try await loaded(reader)
        var writes: [String] = []
        let intent = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
        XCTAssertEqual(writes.count, 0); XCTAssertNil(owner.resultKey)
        XCTAssertTrue(owner.copy(intent) { writes.append($0) })
        XCTAssertFalse(owner.copy(intent) { writes.append($0) })
        XCTAssertEqual(writes, ["  +1 202 555 0100  "])
        XCTAssertEqual(owner.resultKey, "cooperation.phone.copied"); XCTAssertEqual(reader.reads, 1)
    }
    func testMissingAndBlankPhoneCannotCopyNameOrID() async throws {
        let phones: [String?] = [nil, "", "  \n\t"]
        for phone in phones {
            let reader = try Reader(phone: phone), (owner, detail) = try await loaded(reader)
            XCTAssertNil(owner.intent(detail: detail, reader: reader, key: key))
            XCTAssertNil(owner.resultKey); XCTAssertEqual(reader.reads, 1)
        }
    }
    func testWrongDetailDirectionAndReaderAreRejected() async throws {
        let reader = try Reader(), (owner, detail) = try await loaded(reader), other = try Reader()
        XCTAssertNil(owner.intent(detail: detail, reader: reader, key: .init(id: 71, direction: .sent)))
        XCTAssertNil(owner.intent(detail: detail, reader: other, key: key))
        XCTAssertNil(owner.intent(detail: detail, reader: reader, key: .init(id: 72, direction: .received)))
        let returned = try await owner.load(reader: other, key: key)
        XCTAssertEqual(returned, other.value); XCTAssertEqual(other.reads, 1)
        XCTAssertNil(owner.intent(detail: returned, reader: other, key: key))
    }
    func testScopeSwitchSignoutAndDisabledReaderRejectCapturedGesture() async throws {
        for kind in 0..<3 {
            let reader = try Reader(), (owner, detail) = try await loaded(reader)
            let intent = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
            if kind == 0 { reader.scope = UUID() }
            if kind == 1 { reader.isAuthenticated = false }
            if kind == 2 { reader.isConfigured = false }
            var writes = 0
            XCTAssertFalse(owner.copy(intent) { _ in writes += 1 }); XCTAssertEqual(writes, 0)
            XCTAssertNil(owner.resultKey)
        }
    }
    func testBackgroundAndHiddenForegroundCannotReuseOldPhone() async throws {
        let reader = try Reader(), (owner, detail) = try await loaded(reader)
        let old = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
        owner.sceneChanged(active: false); owner.sceneChanged(active: true)
        var writes = 0
        XCTAssertFalse(owner.copy(old) { _ in writes += 1 })
        XCTAssertNil(owner.intent(detail: detail, reader: reader, key: key))
        let fresh = try await owner.load(reader: reader, key: key)
        let next = try XCTUnwrap(owner.intent(detail: fresh, reader: reader, key: key))
        owner.disappear(); owner.sceneChanged(active: true)
        XCTAssertFalse(owner.copy(next) { _ in writes += 1 }); XCTAssertEqual(writes, 0)
        let hiddenRead = try await owner.load(reader: reader, key: key)
        XCTAssertEqual(hiddenRead, reader.value)
        XCTAssertNil(owner.intent(detail: hiddenRead, reader: reader, key: key))
        XCTAssertEqual(reader.reads, 3)
    }
    func testByteDifferentCanonicalEquivalentPhoneAndOldReadAreRejected() async throws {
        let reader = try Reader(phone: "REF-é"), (owner, detail) = try await loaded(reader)
        let old = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
        let changed = try Reader(phone: "REF-e\u{0301}").value
        XCTAssertEqual(detail, changed)
        XCTAssertNil(owner.intent(detail: changed, reader: reader, key: key))
        reader.value = changed
        let fresh = try await owner.load(reader: reader, key: key)
        var writes: [String] = []
        XCTAssertFalse(owner.copy(old) { writes.append($0) })
        let next = try XCTUnwrap(owner.intent(detail: fresh, reader: reader, key: key))
        XCTAssertTrue(owner.copy(next) { writes.append($0) })
        XCTAssertTrue(try XCTUnwrap(writes.first).utf8.elementsEqual("REF-e\u{0301}".utf8))
    }
    func testInjectedFailureReportsFailureAndNewExplicitGestureCanRetry() async throws {
        let reader = try Reader(), (owner, detail) = try await loaded(reader)
        let old = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
        var calls = 0
        XCTAssertFalse(owner.copy(old) { _ in calls += 1; throw APIError.invalidRequest })
        XCTAssertEqual(owner.resultKey, "cooperation.phone.copyFailed")
        XCTAssertFalse(owner.copy(old) { _ in calls += 1 })
        let next = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
        XCTAssertTrue(owner.copy(next) { _ in calls += 1 })
        XCTAssertEqual(calls, 2); XCTAssertEqual(reader.reads, 1)
    }
    func testReentrantCopyAndRetiredCompletionCannotPublishSuccess() async throws {
        let reader = try Reader(), (owner, detail) = try await loaded(reader)
        let intent = try XCTUnwrap(owner.intent(detail: detail, reader: reader, key: key))
        var calls = 0
        XCTAssertTrue(owner.copy(intent) { _ in
            calls += 1
            XCTAssertFalse(owner.copy(intent) { _ in calls += 1 })
            owner.disappear()
        })
        XCTAssertEqual(calls, 1); XCTAssertNil(owner.resultKey)
    }
    func testLateOldReadCannotReplaceNewSuccessfulDetail() async throws {
        let reader = try Reader(), owner = CooperationPhoneCopyOwner(reader: reader, key: key)
        owner.appear(active: true); reader.suspendNext = true
        let old = Task { try await owner.load(reader: reader, key: key) }
        while reader.continuation == nil { await Task.yield() }
        let original = reader.value
        owner.disappear(); reader.scope = UUID(); owner.appear(active: true)
        reader.value = try Reader(phone: "New exact phone").value
        let fresh = try await owner.load(reader: reader, key: key)
        let next = try XCTUnwrap(owner.intent(detail: fresh, reader: reader, key: key))
        reader.continuation?.resume(returning: original); reader.continuation = nil
        let oldReadResult = try await old.value
        XCTAssertEqual(oldReadResult, original)
        var writes: [String] = []
        XCTAssertTrue(owner.copy(next) { writes.append($0) })
        XCTAssertEqual(writes, ["New exact phone"])
    }
}

extension CooperationPhoneCopyOwnerTests {
    func testOriginalDetailReadBeforeFirstAppearReturnsAndThenEnablesCurrentCopy() async throws {
        let reader = try Reader(), owner = CooperationPhoneCopyOwner(reader: reader, key: key)
        let detail = try await owner.load(reader: reader, key: key)
        XCTAssertEqual(detail, reader.value); XCTAssertEqual(reader.reads, 1)
        XCTAssertNil(owner.intent(detail: detail, reader: reader, key: key))
        owner.appear(active: true)
        XCTAssertNotNil(owner.intent(detail: detail, reader: reader, key: key))
    }
    func testRetainedPageTaskBeforeReappearNeverCancelsOriginalDetail() async throws {
        let reader = try Reader(), (owner, before) = try await loaded(reader)
        let old = try XCTUnwrap(owner.intent(detail: before, reader: reader, key: key))
        owner.disappear()
        let returned = try await owner.load(reader: reader, key: key)
        XCTAssertEqual(returned, reader.value); XCTAssertEqual(reader.reads, 2)
        owner.appear(active: true)
        var writes = 0
        XCTAssertFalse(owner.copy(old) { _ in writes += 1 })
        let fresh = try XCTUnwrap(owner.intent(detail: returned, reader: reader, key: key))
        XCTAssertTrue(owner.copy(fresh) { _ in writes += 1 }); XCTAssertEqual(writes, 1)
    }
    func testChangedKeyReadReturnsWithoutOldCopyOwnerInterception() async throws {
        let reader = try Reader(), (oldOwner, before) = try await loaded(reader)
        let old = try XCTUnwrap(oldOwner.intent(detail: before, reader: reader, key: key))
        oldOwner.disappear()
        let newKey = CooperationInviteKey(id: 72, direction: .sent)
        let row = try JSONDecoder().decode(CooperationInvite.self,
            from: Data(#"{"id":72,"partner":{"name":"Synthetic replacement","phone":"New phone"}}"#.utf8))
        reader.value = .init(row: row, occupancy: nil)
        let forwarded = try await oldOwner.load(reader: reader, key: newKey)
        XCTAssertEqual(forwarded, reader.value)
        XCTAssertNil(oldOwner.intent(detail: forwarded, reader: reader, key: newKey))
        let newOwner = CooperationPhoneCopyOwner(reader: reader, key: newKey)
        let accepted = try await newOwner.load(reader: reader, key: newKey)
        newOwner.appear(active: true)
        let next = try XCTUnwrap(newOwner.intent(detail: accepted, reader: reader, key: newKey))
        var writes: [String] = []
        XCTAssertFalse(oldOwner.copy(old) { writes.append($0) })
        XCTAssertTrue(newOwner.copy(next) { writes.append($0) }); XCTAssertEqual(writes, ["New phone"])
    }
    func testReplacementReaderSameKeyGetsItsOwnCopyOwner() async throws {
        let first = try Reader(), (oldOwner, oldDetail) = try await loaded(first)
        let old = try XCTUnwrap(oldOwner.intent(detail: oldDetail, reader: first, key: key))
        oldOwner.disappear()
        let replacement = try Reader(phone: "Replacement exact phone")
        let forwarded = try await oldOwner.load(reader: replacement, key: key)
        XCTAssertEqual(forwarded, replacement.value)
        let owner = CooperationPhoneCopyOwner(reader: replacement, key: key)
        let accepted = try await owner.load(reader: replacement, key: key); owner.appear(active: true)
        var writes: [String] = []
        XCTAssertFalse(oldOwner.copy(old) { writes.append($0) })
        XCTAssertTrue(owner.copy(try XCTUnwrap(owner.intent(detail: accepted, reader: replacement, key: key))) { writes.append($0) })
        XCTAssertEqual(writes, ["Replacement exact phone"])
    }
}

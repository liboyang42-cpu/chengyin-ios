import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real private-home service, request grammar and coordinator with synthetic seams only.
/// The storage fault models do not assert that a real OS Keychain failure has been reproduced.
@available(macOS 14.0, *) @MainActor final class PrivateHomeSaveFailureRecoveryJourneyTests: XCTestCase {
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        var scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var saves: [PrivateHomeMutation] = [], clears: [PrivateHomeMutation] = []
        var failSave = true, writeBeforeFailure = true, failRead = false, failClear = false
        var afterSaveFailure: (() -> Void)?
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> PrivateHomeMutation? {
            if failRead { throw PrivateHomeIssue.storageUnavailable }; return value
        }
        func save(_ mutation: PrivateHomeMutation) throws {
            saves.append(mutation)
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            if !failSave || writeBeforeFailure { value = mutation }
            if failSave { afterSaveFailure?(); throw PrivateHomeIssue.storageUnavailable }
        }
        func clear(matching mutation: PrivateHomeMutation) throws {
            guard !failClear, value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            clears.append(mutation); value = nil
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        let baseURL = URL(string: "https://example.test")!
        var requests: [URLRequest] = [], mutations: [PrivateHomeMutation] = []
        var receipts: [String: [String: Any]] = [:]
        var commits = 0, currentVersion: Int64 = 3, active = true
        var loseNext = false, failCurrent = false, forcedDecision: String?, overrideReceipt: [String: Any]?
        var afterMutation: (() -> Void)?
        var reads: Int { requests.filter { $0.httpMethod == "GET" }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            // Exercise the real shape boundary, not the App's separate live grant selection.
            guard PrivateHomeRequestBoundary.accepts(request, baseURL: baseURL) else { throw PrivateHomeIssue.disabled }
            requests.append(request)
            let data: [String: Any]
            if request.httpMethod == "GET" {
                if failCurrent { throw PrivateHomeIssue.unavailable }
                if active {
                    data = ["version": currentVersion, "status": "ACTIVE", "changedAt": 1, "effectiveAt": 1,
                            "label": "Synthetic", "latitude": 12, "longitude": 45, "datum": "WGS84"]
                } else { data = ["version": currentVersion, "status": "DELETED"] }
            } else {
                let original = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(request.httpBody))
                mutations.append(original)
                if receipts[original.requestId] == nil {
                    let decision = forcedDecision ?? (original.method == "PUT" ? "SAVED" : "DELETED")
                    let version: Int64
                    switch decision {
                    case "SAVED", "DELETED": version = original.expectedVersion + 1; commits += 1; active = decision == "SAVED"
                    case "VERSION_CONFLICT": version = original.expectedVersion + 2
                    case "HOME_CHANGE_COOLDOWN": version = original.expectedVersion
                    default: throw PrivateHomeIssue.invalid
                    }
                    currentVersion = version
                    receipts[original.requestId] = ["requestId": original.requestId, "decision": decision, "version": version]
                }
                afterMutation?()
                if loseNext { loseNext = false; throw PrivateHomeIssue.unknownOutcome }
                data = try XCTUnwrap(overrideReceipt ?? receipts[original.requestId])
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    @MainActor private final class Session {
        var current: PlayExperienceSession?
        init(_ owner: PlayExperienceSession) { current = owner }
    }
    @MainActor private final class Fixture {
        let owner: PlayExperienceSession, session: Session, journal: Journal, wire: Wire, service: PrivateHomeService
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-home", token: "synthetic-token")
            let session = Session(owner), journal = Journal(owner), wire = Wire()
            self.owner = owner; self.session = session; self.journal = journal; self.wire = wire
            service = PrivateHomeService(api: try APIConfiguration(baseURL: wire.baseURL), transport: wire,
                owner: owner, enabled: true, current: { session.current })
        }
        func model(enabled: Bool = true) -> PrivateHomeCoordinator {
            .init(service: service, journal: journal, owner: owner, enabled: enabled, current: { self.session.current })
        }
    }
    private func prepare(_ model: PrivateHomeCoordinator, delete: Bool = false) async throws {
        await model.load(); XCTAssertTrue(model.canEdit)
        if delete { model.prepareDelete() }
        else { model.prepareSet(label: "Synthetic point", point: try .init(latitude: 12, longitude: 45)) }
        XCTAssertTrue(model.canConfirm)
    }
    private func failedSave(_ f: Fixture, _ model: PrivateHomeCoordinator, delete: Bool = false) async throws -> PrivateHomeMutation {
        try await prepare(model, delete: delete); let original = try XCTUnwrap(model.review)
        await model.confirm()
        // Preserve the original initial error presentation and require explicit refresh.
        XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.issue, .storageUnavailable)
        XCTAssertFalse(model.canEdit); XCTAssertFalse(model.canConfirm); XCTAssertFalse(model.canRetry)
        XCTAssertNil(model.review); XCTAssertNil(model.decision); XCTAssertTrue(f.wire.mutations.isEmpty)
        XCTAssertEqual(f.journal.saves, [original]); XCTAssertTrue(f.journal.clears.isEmpty)
        return original
    }
    private func unknown(_ model: PrivateHomeCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .unknown, file: file, line: line)
        XCTAssertFalse(model.canEdit, file: file, line: line); XCTAssertFalse(model.canConfirm, file: file, line: line)
        XCTAssertNil(model.review, file: file, line: line); XCTAssertNil(model.decision, file: file, line: line)
    }

    func testPutAndDeleteSaveErrorsRemainBlockedWithoutAutomaticMutation() async throws {
        for delete in [false, true] {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model, delete: delete)
            await model.confirm(); await model.retryExact(); model.cancelReview()
            model.prepareDelete(); model.prepareSet(label: "Must not stage", point: try .init(latitude: 13, longitude: 46))
            XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(f.journal.value, original)
            XCTAssertEqual(f.journal.saves, [original]); XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertNil(model.review)
        }
    }

    func testExplicitRefreshOfThePersistedOriginalDoesNotReplayOrClear() async throws {
        for delete in [false, true] {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model, delete: delete)
            for _ in 0..<3 { await model.load(); unknown(model) }
            XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.journal.saves, [original]); XCTAssertTrue(f.journal.clears.isEmpty)
            XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertTrue(model.canRetry)
        }
    }

    func testUnprovenEmptySlotCannotUnlockFromCurrentGetOrReinsert() async throws {
        for delete in [false, true] {
            let f = try Fixture(), model = f.model(); f.journal.writeBeforeFailure = false
            let original = try await failedSave(f, model, delete: delete), reads = f.wire.reads
            f.wire.currentVersion = 10
            await model.load(); unknown(model); await model.retryExact(); unknown(model)
            XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertNil(f.journal.value)
            XCTAssertEqual(f.journal.saves, [original]); XCTAssertEqual(f.wire.reads, reads); XCTAssertTrue(f.wire.mutations.isEmpty)
        }
    }

    func testDisappearedOriginalCannotUnlockPutOrDeleteForAnotherReview() async throws {
        for delete in [false, true] {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model, delete: delete)
            f.journal.value = nil; await model.load(); unknown(model)
            model.prepareSet(label: "Replacement", point: try .init(latitude: 13, longitude: 46)); model.prepareDelete()
            await model.confirm(); await model.retryExact(); unknown(model)
            XCTAssertEqual(f.journal.saves, [original]); XCTAssertTrue(f.journal.clears.isEmpty); XCTAssertTrue(f.wire.mutations.isEmpty)
        }
    }

    func testReplacementIdentityMethodVersionLabelAndPointCannotBeAdopted() async throws {
        let point = try PrivateHomePoint(latitude: 12, longitude: 45)
        for change in 0..<5 {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
            let other: PrivateHomeMutation
            switch change {
            case 0: other = try .init(requestId: "replacement", expectedVersion: original.expectedVersion, label: original.label, point: point)
            case 1: other = try .init(requestId: original.requestId, expectedVersion: original.expectedVersion)
            case 2: other = try .init(requestId: original.requestId, expectedVersion: original.expectedVersion + 1, label: original.label, point: point)
            case 3: other = try .init(requestId: original.requestId, expectedVersion: original.expectedVersion, label: "Other label", point: point)
            default: other = try .init(requestId: original.requestId, expectedVersion: original.expectedVersion, label: original.label, point: .init(latitude: 13, longitude: 46))
            }
            f.journal.value = other; let reads = f.wire.reads
            await model.load(); unknown(model); await model.retryExact(); unknown(model)
            XCTAssertEqual(f.journal.value, other); XCTAssertEqual(f.journal.saves, [original]); XCTAssertTrue(f.journal.clears.isEmpty)
            XCTAssertEqual(f.wire.reads, reads); XCTAssertTrue(f.wire.mutations.isEmpty)
            // Only the fixture returns the original. Product code never reconstructs the slot.
            f.journal.value = original; await model.load(); unknown(model); await model.retryExact()
            XCTAssertEqual(f.wire.mutations, [original]); XCTAssertNil(f.journal.value); XCTAssertEqual(model.decision, .saved)
        }
    }

    func testLockedOrCorruptReadRetainsTheAttemptUntilOriginalBecomesReadable() async throws {
        let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
        f.journal.failRead = true; let reads = f.wire.reads
        await model.load(); await model.retryExact(); unknown(model)
        XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertEqual(f.wire.reads, reads); XCTAssertTrue(f.wire.mutations.isEmpty)
        f.journal.failRead = false; await model.load(); unknown(model)
        XCTAssertTrue(f.wire.mutations.isEmpty); await model.retryExact()
        XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.journal.clears, [original]); XCTAssertEqual(f.journal.saves, [original])
    }

    func testForeignJournalScopeCannotEraseOriginalAndRestoringScopeDoesNotReplay() async throws {
        let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
        let foreign = try PlayExperienceSession(accountID: 8, epoch: 1, namespace: "synthetic-home", token: "synthetic-other")
        f.journal.scope = .init(owner: foreign); await model.load(); unknown(model); await model.retryExact()
        XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.wire.mutations.isEmpty)
        f.journal.scope = .init(owner: f.owner); await model.load(); unknown(model)
        XCTAssertTrue(f.wire.mutations.isEmpty); await model.retryExact(); XCTAssertEqual(f.wire.mutations, [original])
    }

    func testExplicitPutAndDeleteRetryUsesExactlyTheReviewedMutationThenFreshGet() async throws {
        for delete in [false, true] {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model, delete: delete)
            await model.load(); unknown(model); await model.retryExact()
            XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.wire.commits, 1)
            XCTAssertEqual(f.journal.saves, [original]); XCTAssertEqual(f.journal.clears, [original]); XCTAssertNil(f.journal.value)
            XCTAssertEqual(model.decision, delete ? .deleted : .saved); XCTAssertEqual(model.home?.version, 4)
            XCTAssertEqual(model.home?.status, delete ? .deleted : .active); XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canEdit)
        }
    }

    func testLostFirstDispatchRetainsOriginalAndSecondExplicitRetryReturnsItsReceipt() async throws {
        for delete in [false, true] {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model, delete: delete)
            await model.load(); f.wire.loseNext = true; await model.retryExact(); unknown(model)
            XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.wire.commits, 1)
            await model.load(); unknown(model); XCTAssertEqual(f.wire.mutations, [original])
            await model.retryExact()
            XCTAssertEqual(f.wire.mutations, [original, original]); XCTAssertEqual(f.wire.commits, 1)
            XCTAssertEqual(f.journal.saves, [original]); XCTAssertEqual(f.journal.clears, [original]); XCTAssertNil(f.journal.value)
            XCTAssertEqual(model.home?.version, 4); XCTAssertEqual(model.decision, delete ? .deleted : .saved)
        }
    }

    func testMalformedOrForeignReceiptNeverClearsOriginalAfterExplicitRetry() async throws {
        let cases: [[String: Any]] = [["requestId": "foreign", "decision": "SAVED", "version": 4],
                                     ["requestId": "overridden-below", "decision": "SAVED", "version": 8]]
        for data in cases {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
            var receipt = data
            if receipt["requestId"] as? String == "overridden-below" { receipt["requestId"] = original.requestId }
            f.wire.overrideReceipt = receipt; await model.load(); await model.retryExact(); unknown(model)
            XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.journal.clears.isEmpty)
            f.wire.overrideReceipt = nil; await model.retryExact()
            XCTAssertEqual(model.decision, .saved); XCTAssertEqual(f.journal.clears, [original]); XCTAssertEqual(f.wire.commits, 1)
        }
    }

    func testReplacementBetweenReplyAndConditionalClearCannotBeErasedOrAdopted() async throws {
        let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
        let other = try PrivateHomeMutation(requestId: "replacement", expectedVersion: 4)
        await model.load(); f.wire.afterMutation = { f.journal.value = other }; await model.retryExact(); unknown(model)
        XCTAssertEqual(f.journal.value, other); XCTAssertTrue(f.journal.clears.isEmpty)
        await model.load(); await model.retryExact(); unknown(model); XCTAssertEqual(f.wire.mutations, [original])
        f.wire.afterMutation = nil; f.journal.value = original; await model.load(); await model.retryExact()
        XCTAssertEqual(f.wire.mutations, [original, original]); XCTAssertEqual(f.wire.commits, 1); XCTAssertEqual(f.journal.clears, [original])
    }

    func testFailedClearAndUnavailableCurrentReadNeverBecomeEditableSuccess() async throws {
        let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
        await model.load(); f.journal.failClear = true; await model.retryExact(); unknown(model)
        XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.journal.clears.isEmpty)
        f.journal.failClear = false; f.wire.failCurrent = true; await model.retryExact()
        XCTAssertEqual(model.decision, .saved); XCTAssertEqual(model.phase, .blocked); XCTAssertNil(model.home); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(f.journal.clears, [original]); XCTAssertNil(f.journal.value); XCTAssertEqual(f.wire.commits, 1)
        f.wire.failCurrent = false; await model.load()
        XCTAssertEqual(model.home?.version, 4); XCTAssertTrue(model.canEdit); XCTAssertEqual(f.wire.mutations, [original, original])
    }

    func testExistingTerminalDenialsStillRequireOriginalReceiptAndFreshReview() async throws {
        for outcome in ["VERSION_CONFLICT", "HOME_CHANGE_COOLDOWN"] {
            let f = try Fixture(), model = f.model(), original = try await failedSave(f, model)
            f.wire.forcedDecision = outcome; await model.load(); await model.retryExact()
            XCTAssertEqual(model.decision?.rawValue, outcome); XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canEdit)
            XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.wire.commits, 0); XCTAssertEqual(f.journal.clears, [original])
            XCTAssertNil(model.review); XCTAssertFalse(model.canConfirm); XCTAssertEqual(f.journal.saves, [original])
            model.prepareSet(label: "New explicit review", point: try .init(latitude: 12, longitude: 45))
            XCTAssertNotEqual(model.review?.requestId, original.requestId); XCTAssertEqual(model.review?.expectedVersion, model.home?.version)
            XCTAssertEqual(f.wire.mutations, [original])
        }
    }

    func testColdRecreationRecoversOnlyAnActuallyStoredOriginalWithoutAutomaticReplay() async throws {
        for delete in [false, true] {
            let f = try Fixture(), first = f.model(), original = try await failedSave(f, first, delete: delete)
            first.invalidate(); let resumed = f.model(); await resumed.load(); unknown(resumed)
            XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.wire.mutations.isEmpty)
            await resumed.retryExact()
            XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.journal.saves, [original]); XCTAssertEqual(f.journal.clears, [original])
            XCTAssertEqual(resumed.decision, delete ? .deleted : .saved)
        }
    }

    func testOwnerRevocationDuringSaveFailureDoesNotRestoreOldPresentationOrDispatch() async throws {
        let f = try Fixture(), model = f.model(); try await prepare(model)
        f.journal.afterSaveFailure = { f.session.current = nil }
        await model.confirm(); await model.load(); await model.retryExact()
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.home); XCTAssertNil(model.review); XCTAssertFalse(model.canRetry)
        XCTAssertNotNil(f.journal.value); XCTAssertTrue(f.journal.clears.isEmpty); XCTAssertTrue(f.wire.mutations.isEmpty)
    }

    func testNormalSaveAndDefaultDisabledPathsRemainUnchanged() async throws {
        let f = try Fixture(), disabled = f.model(enabled: false)
        await disabled.load(); disabled.prepareDelete(); await disabled.confirm(); await disabled.retryExact()
        XCTAssertEqual(disabled.phase, .disabled); XCTAssertTrue(f.journal.saves.isEmpty); XCTAssertTrue(f.wire.requests.isEmpty)
        let model = f.model(); f.journal.failSave = false; try await prepare(model)
        XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertTrue(f.journal.saves.isEmpty)
        let original = try XCTUnwrap(model.review); await model.confirm()
        XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.journal.clears, [original]); XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.decision, .saved); XCTAssertEqual(model.home?.version, 4)
    }
}

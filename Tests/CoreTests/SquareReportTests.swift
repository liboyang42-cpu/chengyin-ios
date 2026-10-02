import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ReportTestAccess: SquareReportAccess {
    var identity: SquareGovernanceIdentity? = .init(accountID: 81, epoch: 1, namespace: "reports-test")
    var token: String? = "synthetic-report-token"
    var version = 3
    var suppliedSubject: SocialActionSnapshot?
    var onSubject: (() async -> Void)?
    func freshSubject(_ target: SocialActionTarget) async throws -> SocialActionSnapshot {
        await onSubject?()
        if let suppliedSubject { return suppliedSubject }
        return try .init(target: target, post: SquareReportFixtures.post(version: version),
            comment: target.commentID.flatMap { id in try SquareReportFixtures.comments().first { $0.id == id } })
    }
}

@MainActor private final class ReportPreflightBarrier {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0
    func arrive() async {
        arrivals += 1
        if arrivals == 2 {
            let suspended = waiters; waiters.removeAll()
            suspended.forEach { $0.resume() }
        } else { await withCheckedContinuation { waiters.append($0) } }
    }
}

@MainActor final class SquareReportTests: XCTestCase {
    private func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com")!) }
    private func coordinator(_ transport: SquareReportFixtureTransport, journal: SquareGovernanceJournal? = nil) throws -> SquareReportCoordinator {
        .init(service: .init(offlineConfiguration: try configuration(), transport: transport), journal: journal ?? .ephemeral())
    }
    private func target(comment: Bool = false) throws -> SquareReportTarget {
        try .init(post: SquareReportFixtures.post(), comment: comment ? SquareReportFixtures.comments().first : nil)
    }
    private func review(_ coordinator: SquareReportCoordinator, access: ReportTestAccess, comment: Bool = false) async throws -> SquareReportReview {
        let snapshot = try await coordinator.load(target: target(comment: comment), access: access)
        return try coordinator.prepare(snapshot: snapshot, reasonCode: "SPAM", description: "Synthetic report facts", access: access)
    }
    func testDefaultServiceCannotReadPolicyOrSubmit() async throws {
        let transport = SquareReportFixtureTransport()
        let service = SquareReportService(configuration: try configuration(), transport: transport)
        XCTAssertFalse(service.readsEnabled); XCTAssertFalse(service.writesEnabled)
        do { _ = try await service.policy(token: "fixture", check: {}); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testPolicyReadsExactVersionedCapabilityAndHasNoFallback() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess()
        let value = try await coordinator(transport).load(target: target(), access: access)
        XCTAssertEqual(value.policy.version, "SYNTHETIC_POLICY_V1"); XCTAssertEqual(value.policy.reasons.count, 13)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/v1/community/capabilities"])
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
    }
    func testPolicyRejectsMissingVersionDuplicateReasonsAndMismatchedCodeList() throws {
        guard case .object(let original) = SquareReportFixtures.policy() else { return XCTFail() }
        for mutation in ["version", "duplicates", "codes"] {
            var raw = original
            if mutation == "version" { raw["policyVersion"] = .string("") }
            if mutation == "duplicates", let rows = raw["reasons"]?.array { raw["reasons"] = .array(rows + [rows[0]]) }
            if mutation == "codes" { raw["reasonCodes"] = .array([.string("OTHER")]) }
            XCTAssertThrowsError(try SquareReportPolicy(raw: .object(raw)))
        }
    }
    func testReasonAndDescriptionRequiredAndUTF16LimitMatchesBackend() async throws {
        let access = ReportTestAccess(), model = try coordinator(.init())
        let snapshot = try await model.load(target: target(), access: access)
        for reason in ["", "NOT_A_SERVER_REASON"] { XCTAssertThrowsError(try model.prepare(snapshot: snapshot, reasonCode: reason, description: "facts", access: access)) }
        XCTAssertThrowsError(try model.prepare(snapshot: snapshot, reasonCode: "SPAM", description: " \n ", access: access))
        XCTAssertThrowsError(try model.prepare(snapshot: snapshot, reasonCode: "SPAM", description: String(repeating: "😀", count: 1001), access: access))
        XCTAssertNoThrow(try model.prepare(snapshot: snapshot, reasonCode: "SPAM", description: String(repeating: "😀", count: 1000), access: access))
    }
    func testRequestContainsExactReviewedReasonVersionTargetDescriptionAndStableID() async throws {
        let access = ReportTestAccess(), model = try coordinator(.init())
        for comment in [false, true] {
            let value = try await review(model, access: access, comment: comment)
            let first = try model.service.command(value, token: access.token!)
            let second = try model.service.command(value, token: access.token!)
            XCTAssertEqual(first.httpBody, second.httpBody); XCTAssertEqual(first.httpMethod, "POST")
            XCTAssertEqual(first.url?.path, "/api/v1/community/reports")
            let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: first.httpBody!) as? [String: Any])
            XCTAssertEqual(Set(fields.keys), ["targetType", "targetId", "reasonCode", "policyVersion", "description", "evidenceAssetIds", "requestId"])
            XCTAssertEqual(fields["targetType"] as? String, comment ? "COMMENT" : "CONTENT")
            XCTAssertEqual(fields["targetId"] as? Int, comment ? 802 : 701)
            XCTAssertEqual(fields["reasonCode"] as? String, "SPAM")
            XCTAssertEqual(fields["policyVersion"] as? String, value.snapshot.policy.version)
            XCTAssertEqual(fields["requestId"] as? String, value.requestID)
            XCTAssertEqual((fields["evidenceAssetIds"] as? [Int])?.count, 0)
        }
    }
    func testPolicyChangeBeforeConfirmationMakesZeroWrites() async throws {
        let transport = SquareReportFixtureTransport(scenario: "reportPolicyChanged"), access = ReportTestAccess()
        let model = try coordinator(transport)
        let value = try await review(model, access: access)
        do { _ = try await model.confirm(value, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareReportFailure, .stale) }
        XCTAssertFalse(transport.requests.contains { $0.httpMethod == "POST" })
    }
    func testContentVersionChangeBeforeConfirmationMakesZeroWrites() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess()
        let actual = try coordinator(transport), value = try await review(actual, access: access)
        access.version = 4
        do { _ = try await actual.confirm(value, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareReportFailure, .stale) }
        XCTAssertFalse(transport.requests.contains { $0.httpMethod == "POST" })
    }
    func testSwitchDuringPolicyReadCannotPrepareForOldAccount() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess()
        transport.onRequest = { _ in await MainActor.run { access.identity = .init(accountID: 82, epoch: 2, namespace: "reports-test") } }
        do { _ = try await coordinator(transport).load(target: target(), access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .signedOut) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testUnknownOutcomeLocksReopenedCoordinatorAndReloginWithoutRetry() async throws {
        let transport = SquareReportFixtureTransport(scenario: "reportUnknown"), access = ReportTestAccess(), journal = SquareGovernanceJournal.ephemeral()
        let model = try coordinator(transport, journal: journal)
        let value = try await review(model, access: access)
        do { _ = try await model.confirm(value, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareReportFailure, .unknown) }
        access.identity = .init(accountID: 81, epoch: 2, namespace: "reports-test")
        let reopened = try coordinator(transport, journal: journal)
        XCTAssertTrue(reopened.isLocked(target: value.snapshot.target, identity: access.identity!))
        let snapshot = try await reopened.load(target: value.snapshot.target, access: access)
        XCTAssertThrowsError(try reopened.prepare(snapshot: snapshot, reasonCode: "SPAM", description: "facts", access: access))
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testReceiptReadbackUsesExactCaseAndNeverUnlocksTarget() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess()
        let model = try coordinator(transport)
        let value = try await review(model, access: access)
        let receipt = try await model.confirm(value, access: access)
        XCTAssertEqual(receipt.stage, "SUBMITTED")
        let updated = try await model.refresh(receipt, target: value.snapshot.target, expectedIdentity: value.snapshot.identity, access: access)
        XCTAssertEqual(updated.publicStage, "IN_REVIEW")
        XCTAssertEqual(transport.requests.last?.url?.path, "/api/community-trust/reports/9901")
        XCTAssertTrue(model.isLocked(target: value.snapshot.target, identity: value.snapshot.identity))
        do { _ = try await model.confirm(value, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareReportFailure, .locked) }
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testLegacyOrUnknownObjectsCannotBeReinterpretedAsVersionedReportTargets() throws {
        XCTAssertThrowsError(try SquareReportTarget(post: SquareSyntheticFixtures.post()))
        let raw = try JSONDecoder().decode(SquarePost.self, from: SquareReportFixtures.postData())
        XCTAssertThrowsError(try SquareReportTarget(post: raw))
        XCTAssertThrowsError(try SquareReportTarget(post: SquareReportFixtures.post(), comment: SquareReportFixtures.comments(postID: 702).first))
    }
    func testOwnCommentAndExpiredSnapshotCannotBeReviewed() async throws {
        let access = ReportTestAccess(); access.identity = .init(accountID: 82, epoch: 1, namespace: "reports-test")
        let model = try coordinator(.init())
        do { _ = try await model.load(target: target(comment: true), access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .invalid) }
        access.identity = .init(accountID: 81, epoch: 1, namespace: "reports-test")
        let snapshot = try await model.load(target: target(), access: access)
        XCTAssertThrowsError(try model.prepare(snapshot: snapshot, reasonCode: "SPAM", description: "facts", access: access, now: snapshot.observedAt.addingTimeInterval(301)))
    }
    func testAcknowledgedCaseReferenceSurvivesCoordinatorReplacementWithoutStoringDescription() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess()
        let journal = SquareGovernanceJournal.ephemeral(), store = SquareReportCaseStore.ephemeral()
        let service = SquareReportService(offlineConfiguration: try configuration(), transport: transport)
        let first = SquareReportCoordinator(service: service, journal: journal, caseStore: store)
        let value = try await review(first, access: access)
        _ = try await first.confirm(value, access: access)
        access.identity = .init(accountID: 81, epoch: 2, namespace: "reports-test")
        let reopened = SquareReportCoordinator(service: service, journal: journal, caseStore: store)
        let restored = try await reopened.recover(target: value.snapshot.target, expectedIdentity: access.identity!, access: access)
        XCTAssertEqual(restored?.id, 9901); XCTAssertEqual(restored?.publicStage, "IN_REVIEW")
        XCTAssertTrue(reopened.isLocked(target: value.snapshot.target, identity: access.identity!))
        access.identity = .init(accountID: 82, epoch: 3, namespace: "reports-test")
        let foreign = try await reopened.recover(target: value.snapshot.target, expectedIdentity: access.identity!, access: access)
        XCTAssertNil(foreign)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testTwoCoordinatorsSuspendedInPreflightCanClaimTargetOnlyOnce() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess(), journal = SquareGovernanceJournal.ephemeral()
        let first = try coordinator(transport, journal: journal), second = try coordinator(transport, journal: journal)
        let a = try await review(first, access: access), b = try await review(second, access: access)
        XCTAssertNotEqual(a.requestID, b.requestID)
        let barrier = ReportPreflightBarrier(); access.onSubject = { await barrier.arrive() }
        let one = Task { @MainActor () -> Result<SquareReportReceipt, Error> in
            do { return .success(try await first.confirm(a, access: access)) } catch { return .failure(error) }
        }
        let two = Task { @MainActor () -> Result<SquareReportReceipt, Error> in
            do { return .success(try await second.confirm(b, access: access)) } catch { return .failure(error) }
        }
        let outcomes = await [one.value, two.value]
        XCTAssertEqual(barrier.arrivals, 2)
        XCTAssertEqual(outcomes.filter { if case .success = $0 { return true }; return false }.count, 1)
        let failures = outcomes.compactMap { result -> SquareReportFailure? in if case .failure(let error) = result { return error as? SquareReportFailure }; return nil }
        XCTAssertEqual(failures, [.locked])
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testChangedTargetReloadRequiresNewReviewAndNeverRetriesOldMutation() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess(), model = try coordinator(transport)
        let old = try await review(model, access: access); access.version = 4
        do { _ = try await model.confirm(old, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareReportFailure, .stale) }
        let fresh = try await model.reload(target: old.snapshot.target, access: access)
        XCTAssertEqual(fresh.target.version, 4); XCTAssertEqual(fresh.target.source, old.snapshot.target.source)
        XCTAssertFalse(transport.requests.contains { $0.httpMethod == "POST" })
        let replacement = try model.prepare(snapshot: fresh, reasonCode: "SPAM", description: old.description, access: access)
        XCTAssertNotEqual(replacement.requestID, old.requestID)
        _ = try await model.confirm(replacement, access: access)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testExpiredSnapshotCanReloadBeforePreparingNewReview() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess(), model = try coordinator(transport)
        let old = try await model.load(target: target(), access: access)
        XCTAssertThrowsError(try model.prepare(snapshot: old, reasonCode: "SPAM", description: "Saved facts", access: access, now: old.observedAt.addingTimeInterval(301)))
        let fresh = try await model.reload(target: old.target, access: access)
        XCTAssertNoThrow(try model.prepare(snapshot: fresh, reasonCode: "SPAM", description: "Saved facts", access: access))
        XCTAssertFalse(transport.requests.contains { $0.httpMethod == "POST" })
    }
    func testReloadCannotAdoptLegacyOrDifferentSubjectWithAnEqualLookingID() async throws {
        let transport = SquareReportFixtureTransport(), access = ReportTestAccess(), model = try coordinator(transport)
        access.suppliedSubject = try .init(target: .post(701), post: SquareSyntheticFixtures.post())
        do { _ = try await model.reload(target: target(), access: access); XCTFail() } catch {}
        access.suppliedSubject = try .init(target: .post(702), post: SquareReportFixtures.post(id: 702))
        do { _ = try await model.reload(target: target(), access: access); XCTFail() } catch {}
        access.suppliedSubject = try .init(target: .post(701), post: SquareReportFixtures.post())
        do { _ = try await model.reload(target: target(comment: true), access: access); XCTFail() } catch {}
        XCTAssertFalse(transport.requests.contains { $0.httpMethod == "POST" })
    }

}

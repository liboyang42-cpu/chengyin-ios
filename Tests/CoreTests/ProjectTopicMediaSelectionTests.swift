import Foundation
import XCTest
@testable import QuestifyCore

final class ProjectTopicMediaSelectionTests: XCTestCase {
    private typealias F = ProjectTopicMediaTestSupport
    private struct Prepared {
        let owner: ProjectTopicMediaSelection
        let context: ProjectTopicMediaContext
        let policy: ProjectTopicMediaPolicy
        let ticket: ProjectTopicMediaSelection.Ticket
        let requests: [ProjectTopicMediaInspectionRequest]
    }
    private func prepared(policy: ProjectTopicMediaPolicy? = nil, count: Int = 1) throws -> Prepared {
        let context = try F.context(), policy = try policy ?? F.policy()
        let owner = ProjectTopicMediaSelection(context: context, policy: policy)
        let ticket = try XCTUnwrap(owner.begin(visit: owner.visit, context: context, policy: policy))
        let requests = try XCTUnwrap(owner.prepareInspection((0..<count).map { _ in F.reference() }, ticket: ticket, context: context, policy: policy))
        return .init(owner: owner, context: context, policy: policy, ticket: ticket, requests: requests)
    }
    private func preview(_ p: Prepared) throws -> ProjectTopicMediaSelection.Preview {
        let evidence = try p.requests.map { try ProjectTopicMediaInspectionEvidence.inspect($0, using: F.Inspector()) }
        return try XCTUnwrap(p.owner.finishInspection(evidence, ticket: p.ticket, context: p.context, policy: p.policy))
    }
    func testMissingPolicyOrContextIsExplicitlyUnavailableWithoutFallback() throws {
        let context = try F.context(), policy = try F.policy()
        let noPolicy = ProjectTopicMediaSelection(context: context, policy: nil)
        XCTAssertEqual(noPolicy.state, .unavailable(.policyUnavailable))
        XCTAssertNil(noPolicy.begin(visit: noPolicy.visit, context: context, policy: policy))
        let noContext = ProjectTopicMediaSelection(context: nil, policy: policy)
        XCTAssertEqual(noContext.state, .unavailable(.contextUnavailable))
        XCTAssertNil(noContext.begin(visit: noContext.visit, context: context, policy: policy))
    }
    func testBeginIsSingleFlightAndOldCancelCannotCancelReplacementTicket() throws {
        let context = try F.context(), policy = try F.policy(), owner = ProjectTopicMediaSelection(context: context, policy: policy)
        let first = try XCTUnwrap(owner.begin(visit: owner.visit, context: context, policy: policy))
        XCTAssertNil(owner.begin(visit: owner.visit, context: context, policy: policy))
        owner.cancel(first)
        let second = try XCTUnwrap(owner.begin(visit: owner.visit, context: context, policy: policy)); owner.cancel(first)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(owner.state, .picking(second))
        XCTAssertNil(owner.prepareInspection([F.reference()], ticket: first, context: context, policy: policy))
    }
    func testFreshInspectionPreviewAndConfirmReturnOnlyOneLocalIntent() throws {
        let p = try prepared(), view = try preview(p)
        XCTAssertEqual(p.owner.state, .preview(view))
        let intent = try XCTUnwrap(p.owner.confirm(view, context: p.context, policy: p.policy))
        XCTAssertEqual(intent.items, view.items); XCTAssertEqual(intent.context, p.context)
        XCTAssertEqual(p.owner.state, .accepted(intent)); XCTAssertNil(p.owner.confirm(view, context: p.context, policy: p.policy))
        XCTAssertNil(p.owner.begin(visit: p.owner.visit, context: p.context, policy: p.policy))
        XCTAssertEqual(intent.localRecord.items, view.items)
    }
    func testCancelInspectionInvalidatesReadBudgetAndRejectsLateEvidence() throws {
        let p = try prepared(); p.owner.cancel(p.ticket)
        XCTAssertEqual(p.owner.state, .idle)
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(p.requests[0], using: F.Inspector())) { XCTAssertEqual($0 as? ProjectTopicMediaFailure, .changedContext) }
        XCTAssertNil(p.owner.finishInspection([], ticket: p.ticket, context: p.context, policy: p.policy))
        let newer = try XCTUnwrap(p.owner.begin(visit: p.owner.visit, context: p.context, policy: p.policy))
        p.owner.inspectionFailed(.invalidInspection, ticket: p.ticket)
        XCTAssertEqual(p.owner.state, .picking(newer))
    }
    func testCancelPreviewAndBackRetirementNeverReturnAnIntent() throws {
        let p = try prepared(), view = try preview(p); p.owner.cancel(p.ticket)
        XCTAssertEqual(p.owner.state, .idle); XCTAssertNil(p.owner.confirm(view, context: p.context, policy: p.policy))
        let q = try prepared(), other = try preview(q); q.owner.retire()
        XCTAssertEqual(q.owner.state, .closed); XCTAssertNil(q.owner.confirm(other, context: q.context, policy: q.policy))
        q.owner.synchronize(context: q.context, policy: q.policy); XCTAssertEqual(q.owner.state, .closed)
    }
    func testAccountDeploymentEpochDraftProductOwnerRevisionAndVisitChangesRejectPreview() throws {
        let changed = [try F.context(account: 8), try F.context(epoch: 2), try F.context(namespace: "other"),
                       try F.context(viewer: 1), try F.context(configuration: 1), try F.context(revision: 2),
                       try F.context(visit: UUID()), try F.context(identity: .init()), try F.context(identity: .init(topicID: 42)),
                       try F.context(product: .freeExplore), try F.context(owner: .merchant)]
        for context in changed {
            let p = try prepared(), view = try preview(p)
            XCTAssertNil(p.owner.confirm(view, context: context, policy: p.policy))
            XCTAssertEqual(p.owner.state, .unavailable(.changedContext))
        }
        let p = try prepared(), view = try preview(p)
        XCTAssertNil(p.owner.confirm(view, context: nil, policy: p.policy))
    }
    func testExternalABAAndSameBytesWithNewRevisionCannotReviveOldVisit() throws {
        let p = try prepared(), view = try preview(p), oldVisit = p.owner.visit
        p.owner.synchronize(context: try F.context(revision: 2), policy: p.policy)
        p.owner.synchronize(context: p.context, policy: p.policy)
        XCTAssertNotEqual(p.owner.visit, oldVisit)
        XCTAssertNil(p.owner.confirm(view, context: p.context, policy: p.policy))
        XCTAssertNil(p.owner.begin(visit: oldVisit, context: p.context, policy: p.policy))
        let q = try prepared(); q.owner.synchronize(context: try F.context(revision: 3), policy: q.policy)
        XCTAssertThrowsError(try ProjectTopicMediaInspectionEvidence.inspect(q.requests[0], using: F.Inspector()))
    }
    func testPolicyWithdrawalAndSameIDChangedLimitsInvalidateOldPreview() throws {
        for policy in [Optional<ProjectTopicMediaPolicy>.none, try F.policy(bytes: 49), try F.policy(revision: 2), try F.policy(mixing: .singleKind)] {
            let p = try prepared(), view = try preview(p)
            XCTAssertNil(p.owner.confirm(view, context: p.context, policy: policy))
            p.owner.synchronize(context: p.context, policy: p.policy)
            XCTAssertNil(p.owner.confirm(view, context: p.context, policy: p.policy))
        }
    }
    func testEmptyDuplicateAndOverLimitReferencesFailBeforeAnyInspection() throws {
        let same = F.reference(), alias = ProjectTopicMediaLocalReference(id: same.id, revision: UUID())
        for refs in [[], [same, same], [same, alias], [F.reference(), F.reference(), F.reference(), F.reference()]] {
            let context = try F.context(), policy = try F.policy(), owner = ProjectTopicMediaSelection(context: context, policy: policy)
            let ticket = try XCTUnwrap(owner.begin(visit: owner.visit, context: context, policy: policy))
            XCTAssertNil(owner.prepareInspection(refs, ticket: ticket, context: context, policy: policy))
            if refs.isEmpty { XCTAssertEqual(owner.state, .failed(.noSelection)) }
            else if refs.count > 3 { XCTAssertEqual(owner.state, .failed(.tooManyItems)) }
            else { XCTAssertEqual(owner.state, .failed(.invalidReference)) }
        }
    }
    func testForeignTicketReorderedOrMissingEvidenceCannotBecomePreview() throws {
        for mode in 0..<3 {
            let p = try prepared(count: 2)
            var evidence = try p.requests.map { try ProjectTopicMediaInspectionEvidence.inspect($0, using: F.Inspector()) }
            if mode == 0 { evidence.reverse() }
            if mode == 1 { evidence.removeLast() }
            if mode == 2 {
                let other = try prepared()
                evidence[0] = try ProjectTopicMediaInspectionEvidence.inspect(other.requests[0], using: F.Inspector())
            }
            XCTAssertNil(p.owner.finishInspection(evidence, ticket: p.ticket, context: p.context, policy: p.policy))
            XCTAssertEqual(p.owner.state, .failed(.invalidInspection))
        }
    }
    func testMixingDependsOnlyOnInjectedPolicyAndImageOrderIsPreserved() throws {
        for mixing in [ProjectTopicMediaPolicy.Mixing.singleKind, .mixed] {
            let p = try prepared(policy: F.policy(mixing: mixing), count: 2)
            let image = try ProjectTopicMediaInspectionEvidence.inspect(p.requests[0], using: F.Inspector())
            let video = F.Inspector(); video.kind = .video; video.mime = "video/mp4"; video.duration = 1000
            let movie = try ProjectTopicMediaInspectionEvidence.inspect(p.requests[1], using: video)
            let result = p.owner.finishInspection([image, movie], ticket: p.ticket, context: p.context, policy: p.policy)
            if mixing == .mixed { XCTAssertEqual(result?.items.map(\.kind), [.image, .video]); XCTAssertEqual(result?.items.map(\.reference), p.requests.map(\.reference)) }
            else { XCTAssertNil(result); XCTAssertEqual(p.owner.state, .failed(.mixedKinds)) }
        }
    }
    func testColdMetadataRestoreRequiresSameOwnerDraftAndFreshInspectionBeforeIntent() throws {
        let old = try F.accepted(), record = try ProjectTopicMediaLocalRecord.decode(old.localRecord.encoded(), maximumRecordBytes: 100_000)
        let current = try F.context(epoch: 2, revision: 0, visit: UUID()), policy = try F.policy()
        let owner = try ProjectTopicMediaSelection.restoring(record, context: current, policy: policy)
        XCTAssertEqual(owner.state, .needsReinspection); XCTAssertEqual(owner.restoredRecord, record)
        let ticket = try XCTUnwrap(owner.begin(visit: owner.visit, context: current, policy: policy))
        let requests = try XCTUnwrap(owner.prepareInspection(record.items.map(\.reference), ticket: ticket, context: current, policy: policy))
        let evidence = try requests.map { try ProjectTopicMediaInspectionEvidence.inspect($0, using: F.Inspector()) }
        let preview = try XCTUnwrap(owner.finishInspection(evidence, ticket: ticket, context: current, policy: policy))
        let intent = try XCTUnwrap(owner.confirm(preview, context: current, policy: policy))
        XCTAssertEqual(intent.items, record.items); XCTAssertEqual(intent.context.session.epoch, 2)
        let absentPolicy = try ProjectTopicMediaSelection.restoring(record, context: current, policy: nil)
        XCTAssertEqual(absentPolicy.state, .unavailable(.policyUnavailable))
        XCTAssertNil(absentPolicy.begin(visit: absentPolicy.visit, context: current, policy: nil))
        for changed in [try F.context(account: 8), try F.context(namespace: "other"), try F.context(identity: .init()), try F.context(product: .freeExplore), try F.context(owner: .merchant)] {
            XCTAssertThrowsError(try ProjectTopicMediaSelection.restoring(record, context: changed, policy: policy))
        }
    }
    func testRecoveryRejectsChangedFileFactsAndCannotSubstituteNewReference() throws {
        let record = try F.accepted().localRecord, context = try F.context(), policy = try F.policy()
        let owner = try ProjectTopicMediaSelection.restoring(record, context: context, policy: policy)
        let ticket = try XCTUnwrap(owner.begin(visit: owner.visit, context: context, policy: policy))
        XCTAssertNil(owner.prepareInspection([F.reference()], ticket: ticket, context: context, policy: policy))
        XCTAssertEqual(owner.state, .failed(.changedSource))
        let second = try XCTUnwrap(owner.begin(visit: owner.visit, context: context, policy: policy))
        let requests = try XCTUnwrap(owner.prepareInspection(record.items.map(\.reference), ticket: second, context: context, policy: policy))
        let changed = F.Inspector(); changed.chunks = [Data("different".utf8)]
        let evidence = try ProjectTopicMediaInspectionEvidence.inspect(requests[0], using: changed)
        XCTAssertNil(owner.finishInspection([evidence], ticket: second, context: context, policy: policy))
        XCTAssertEqual(owner.state, .failed(.changedSource)); XCTAssertEqual(owner.restoredRecord, record)
    }
}

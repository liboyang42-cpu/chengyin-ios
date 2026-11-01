import Foundation
import XCTest
@testable import QuestifyCore

private func proof(publisher: Bool = true, actor: Int = 5, topic: Int = 70) -> ChapterReplacementInvitationPublisherProof {
    ChapterReplacementInvitationPublisherProof(topicID: topic, actorAccountID: actor,
                                               isFreshTopicPublisher: publisher, projectManageOwnerMapped: true)
}

final class ChapterReplacementInvitationTests: XCTestCase {
    private func value(_ json: String) throws -> MerchantContentValue {
        try JSONDecoder().decode(MerchantContentValue.self, from: Data(json.utf8))
    }
    private func access(_ json: String) throws -> MerchantAccess {
        try JSONDecoder().decode(MerchantAccess.self, from: Data(json.utf8))
    }
    private var ownerAccess: MerchantAccess {
        get throws {
            try access(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}"#)
        }
    }
    private var managerAccess: MerchantAccess {
        get throws {
            try access(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:project:manage"]}"#)
        }
    }
    private var vacancyRow: String { #"{"offerId":900,"topicId":70,"chapterId":7,"status":0,"withdrawReason":"原商家退出","merchantMemberId":11}"# }
    private var candidateRow: String { #"{"merchantMemberId":42,"chapterId":7,"replacementOfOfferId":900,"merchantName":"候选商家"}"# }

    func testFreshTopicReadProofFailsClosedUnlessMemberAndOwnerAgree() throws {
        let document = try value("{\"id\":70,\"memberId\":5,\"isOwner\":1}")
        let proof = try XCTUnwrap(ChapterReplacementInvitationPublisherProof.fromFreshTopicRead(
            topicID: 70, actorAccountID: 5, document: document, projectManageOwnerMapped: true))
        XCTAssertTrue(proof.verified)
        XCTAssertFalse(try XCTUnwrap(ChapterReplacementInvitationPublisherProof.fromFreshTopicRead(
            topicID: 70, actorAccountID: 5, document: document, projectManageOwnerMapped: false)).verified)
        for raw in ["{\"id\":70,\"memberId\":9,\"isOwner\":1}", "{\"id\":70,\"isOwner\":1}",
                    "{\"id\":70,\"memberId\":5,\"isOwner\":0}", "{\"memberId\":5,\"isOwner\":1}", "{\"id\":71,\"memberId\":5,\"isOwner\":1}"] {
            XCTAssertNil(ChapterReplacementInvitationPublisherProof.fromFreshTopicRead(
                topicID: 70, actorAccountID: 5, document: try value(raw), projectManageOwnerMapped: true))
        }
    }

    func testInvitableRequestRequiresTopicAndAllowsNoLocation() throws {
        let plain = try ChapterReplacementInvitationInvitableRequest(topicID: 70)
        XCTAssertEqual(plain.fields(), ["topicId": .integer(70)])
        let located = try ChapterReplacementInvitationInvitableRequest(
            topicID: 70, coordinates: ChapterReplacementInvitationCoordinates(latitude: 31.2, longitude: 121.5))
        XCTAssertEqual(Set(located.fields().keys), ["topicId", "latitude", "longitude"])
        XCTAssertThrowsError(try ChapterReplacementInvitationInvitableRequest(topicID: 0))
        XCTAssertThrowsError(try ChapterReplacementInvitationCoordinates(latitude: 91, longitude: 0))
        XCTAssertThrowsError(try ChapterReplacementInvitationCoordinates(latitude: .nan, longitude: 0))
    }

    func testInviteFieldsCarryExactTripleOptionalMessageAndScope() throws {
        let plan = try ChapterReplacementInvitationPlan.make(
            topicID: 70, scope: .merchant, actorAccountID: 5, merchantAccess: ownerAccess,
            publisherProof: proof(), vacancy: ChapterReplacementInvitationVacancy(row: value(vacancyRow)),
            candidate: ChapterReplacementInvitationCandidate(row: value(candidateRow)), existing: [], message: "  请补位  ")
        XCTAssertEqual(plan.inviteFields(), [
            "chapterId": .integer(7), "merchantMemberId": .integer(42),
            "replacementOfOfferId": .integer(900), "message": .string("请补位"), "scope": .string("MERCHANT"),
        ])
        XCTAssertEqual(ChapterReplacementInvitationPlan.invitePath, "api/merchant/chapter-application/invite")
        let impact = ChapterReplacementInvitationImpact(plan: plan)
        XCTAssertTrue(impact.createsPendingInvite)
        XCTAssertFalse(impact.autoAccepts); XCTAssertFalse(impact.fillsSupply); XCTAssertFalse(impact.triggersPaymentOrRefund)
    }

    func testCurrentMemberScopeOmitsScopeAndNeedsNoMerchantAccess() throws {
        let plan = try ChapterReplacementInvitationPlan.make(
            topicID: 70, scope: .currentMember, actorAccountID: 5, merchantAccess: nil,
            publisherProof: proof(), vacancy: ChapterReplacementInvitationVacancy(row: value(vacancyRow)),
            candidate: ChapterReplacementInvitationCandidate(row: value(candidateRow)), existing: [])
        XCTAssertNil(plan.inviteFields()["scope"])
        XCTAssertNil(plan.inviteFields()["message"])
    }

    func testMerchantScopeRequiresOwnerMappedProjectManage() throws {
        let vacancy = try ChapterReplacementInvitationVacancy(row: value(vacancyRow))
        let candidate = try ChapterReplacementInvitationCandidate(row: value(candidateRow))
        // Manager holding the raw permission is not the owner mapping.
        XCTAssertThrowsError(try ChapterReplacementInvitationPlan.make(
            topicID: 70, scope: .merchant, actorAccountID: 5, merchantAccess: managerAccess,
            publisherProof: proof(), vacancy: vacancy, candidate: candidate, existing: [])) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .denied)
        }
        XCTAssertThrowsError(try ChapterReplacementInvitationPlan.make(
            topicID: 70, scope: .merchant, actorAccountID: 5, merchantAccess: nil,
            publisherProof: proof(), vacancy: vacancy, candidate: candidate, existing: []))
    }

    func testNonPublisherCannotInviteInEitherScope() throws {
        // e.g. a COOP_MANAGE-style employee who is not the real topic publisher.
        let vacancy = try ChapterReplacementInvitationVacancy(row: value(vacancyRow))
        let candidate = try ChapterReplacementInvitationCandidate(row: value(candidateRow))
        for scope in [ChapterReplacementInvitationScope.merchant, .currentMember] {
            XCTAssertThrowsError(try ChapterReplacementInvitationPlan.make(
                topicID: 70, scope: scope, actorAccountID: 5, merchantAccess: ownerAccess,
                publisherProof: proof(publisher: false), vacancy: vacancy, candidate: candidate, existing: [])) {
                XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .notTopicPublisher)
            }
        }
    }

    func testVacancyMustBeStatusZeroWithWithdrawReasonInSameTopicChapter() throws {
        XCTAssertThrowsError(try ChapterReplacementInvitationVacancy(
            row: value(#"{"offerId":900,"topicId":70,"chapterId":7,"status":1,"withdrawReason":"x","merchantMemberId":11}"#)))
        XCTAssertThrowsError(try ChapterReplacementInvitationVacancy(
            row: value(#"{"offerId":900,"topicId":70,"chapterId":7,"status":0,"withdrawReason":"  ","merchantMemberId":11}"#)))
        XCTAssertThrowsError(try ChapterReplacementInvitationVacancy(
            row: value(#"{"offerId":900,"topicId":70,"chapterId":7,"status":0,"merchantMemberId":11}"#)))
    }

    func testCandidateMustMatchVacancyChapterOfferAndNotBeOriginalMerchant() throws {
        let vacancy = try ChapterReplacementInvitationVacancy(row: value(vacancyRow))
        func plan(_ row: String) throws -> ChapterReplacementInvitationPlan {
            try ChapterReplacementInvitationPlan.make(
                topicID: 70, scope: .currentMember, actorAccountID: 5, merchantAccess: nil,
                publisherProof: proof(), vacancy: vacancy,
                candidate: ChapterReplacementInvitationCandidate(row: value(row)), existing: [])
        }
        XCTAssertThrowsError(try plan(#"{"merchantMemberId":42,"chapterId":8,"replacementOfOfferId":900}"#))
        XCTAssertThrowsError(try plan(#"{"merchantMemberId":42,"chapterId":7,"replacementOfOfferId":901}"#))
        XCTAssertThrowsError(try plan(#"{"merchantMemberId":11,"chapterId":7,"replacementOfOfferId":900}"#)) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .originalMerchant)
        }
        // Legacy candidate alias is accepted only when it agrees with the contract name.
        XCTAssertThrowsError(try ChapterReplacementInvitationCandidate(
            row: value(#"{"merchantMemberId":42,"memberId":43,"chapterId":7,"replacementOfOfferId":900}"#)))
        XCTAssertNoThrow(try ChapterReplacementInvitationCandidate(
            row: value(#"{"memberId":42,"chapterId":7,"replacementOfOfferId":900}"#)))
    }

    func testMultipleVacanciesAndSameMerchantAcrossChaptersStayDistinct() throws {
        let rows = try [
            value(#"{"offerId":900,"topicId":70,"chapterId":7,"status":0,"withdrawReason":"a","merchantMemberId":11}"#),
            value(#"{"offerId":901,"topicId":70,"chapterId":8,"status":0,"withdrawReason":"b","merchantMemberId":12}"#),
            value(#"{"offerId":902,"topicId":71,"chapterId":7,"status":0,"withdrawReason":"c","merchantMemberId":13}"#),
        ]
        let vacancies = ChapterReplacementInvitationVacancy.vacancies(rows: rows)
        XCTAssertEqual(vacancies.map(\.offerID), [900, 901, 902])
        let candidateRows = try [
            value(#"{"merchantMemberId":42,"chapterId":7,"replacementOfOfferId":900}"#),
            value(#"{"merchantMemberId":42,"chapterId":8,"replacementOfOfferId":901}"#),
        ]
        XCTAssertEqual(ChapterReplacementInvitationCandidate.candidates(rows: candidateRows, vacancy: vacancies[0]).map(\.chapterID), [7])
        XCTAssertEqual(ChapterReplacementInvitationCandidate.candidates(rows: candidateRows, vacancy: vacancies[1]).map(\.chapterID), [8])
    }

    func testExistingReplacementOrPendingApprovedApplicationBlocks() throws {
        let vacancy = try ChapterReplacementInvitationVacancy(row: value(vacancyRow))
        let candidate = try ChapterReplacementInvitationCandidate(row: value(candidateRow))
        func make(_ existingJSON: String) throws -> ChapterReplacementInvitationPlan {
            try ChapterReplacementInvitationPlan.make(
                topicID: 70, scope: .currentMember, actorAccountID: 5, merchantAccess: nil,
                publisherProof: proof(), vacancy: vacancy, candidate: candidate,
                existing: ChapterReplacementInvitationExisting.existing(rows: [value(existingJSON)]))
        }
        for blocked in [
            #"{"id":1,"chapterId":9,"merchantId":99,"status":0,"replacementOfOfferId":900}"#,
            #"{"id":1,"chapterId":7,"merchantId":42,"status":1}"#,
            #"{"id":1,"chapterId":7,"merchantId":42,"status":0,"source":1}"#,
        ] {
            XCTAssertThrowsError(try make(blocked)) { XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .alreadyReplaced) }
        }
        XCTAssertNoThrow(try make(#"{"id":1,"chapterId":7,"merchantId":42,"status":2}"#))
        XCTAssertNoThrow(try make(#"{"id":1,"chapterId":8,"merchantId":42,"status":0}"#))
    }

    func testOwnerRequestsAndExactTupleReadback() throws {
        let plan = try ChapterReplacementInvitationPlan.make(
            topicID: 70, scope: .merchant, actorAccountID: 5, merchantAccess: ownerAccess,
            publisherProof: proof(), vacancy: ChapterReplacementInvitationVacancy(row: value(vacancyRow)),
            candidate: ChapterReplacementInvitationCandidate(row: value(candidateRow)), existing: [])
        XCTAssertEqual(try ChapterReplacementInvitationOwnerListRequest(topicID: 70, scope: .merchant).fields(),
                       ["topicId": .integer(70), "scope": .string("MERCHANT")])
        XCTAssertEqual(ChapterReplacementInvitationOwnerMineRequest(scope: .merchant).fields(), ["scope": .string("MERCHANT")])
        XCTAssertEqual(ChapterReplacementInvitationOwnerMineRequest(scope: .currentMember).fields(), [:])
        let row = try value(#"{"id":55,"topicId":70,"chapterId":7,"merchantId":42,"replacementOfOfferId":900,"source":1,"status":0}"#)
        XCTAssertEqual(try ChapterReplacementInvitationReadback.verify(rows: [row], plan: plan).applicationID, 55)
        let aliasOnly = try value(#"{"id":55,"topicId":70,"chapterId":7,"merchantMemberId":42,"replacementOfOfferId":900,"source":1,"status":0}"#)
        XCTAssertThrowsError(try ChapterReplacementInvitationReadback.verify(rows: [aliasOnly], plan: plan)) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .notFound)
        }
        // Missing replacementOfOfferId in the tuple can never verify, even if the rest matches.
        let incomplete = try value(#"{"id":55,"topicId":70,"chapterId":7,"merchantId":42,"source":1,"status":0}"#)
        XCTAssertThrowsError(try ChapterReplacementInvitationReadback.verify(rows: [incomplete], plan: plan)) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .notFound)
        }
        let approved = try value(#"{"id":55,"topicId":70,"chapterId":7,"merchantId":42,"replacementOfOfferId":900,"source":1,"status":1}"#)
        XCTAssertThrowsError(try ChapterReplacementInvitationReadback.verify(rows: [approved], plan: plan)) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .stateMismatch)
        }
        XCTAssertThrowsError(try ChapterReplacementInvitationReadback.verify(rows: [row, row], plan: plan)) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .duplicateReadback)
        }
        // The same application appearing on both owner legs is one match, not a duplicate.
        XCTAssertEqual(try ChapterReplacementInvitationReadback.verify(ownerList: [row], ownerMine: [row], plan: plan).applicationID, 55)
    }
}

@MainActor
final class ChapterReplacementInvitationCoordinatorTests: XCTestCase {
    private func value(_ json: String) throws -> MerchantContentValue {
        try JSONDecoder().decode(MerchantContentValue.self, from: Data(json.utf8))
    }

    private final class Fake {
        var vacancyRows: [MerchantContentValue] = []
        var candidateRows: [MerchantContentValue] = []
        var existingRows: [MerchantContentValue] = []
        var ownerListRows: [MerchantContentValue] = []
        var ownerMineRows: [MerchantContentValue] = []
        var sendError: Error?
        var releaseError: Error?
        var sends = 0
        var candidateRequests: [ChapterReplacementInvitationInvitableRequest] = []
        var vacancyLoads = 0
    }

    private func coordinator(_ fake: Fake, intents: any ChapterReplacementInvitationIntentStoring = ChapterReplacementInvitationMemoryIntents()) -> ChapterReplacementInvitationCoordinator {
        ChapterReplacementInvitationCoordinator(effects: .init(
            loadVacancyRows: { _ in fake.vacancyLoads += 1; return fake.vacancyRows },
            loadCandidateRows: { request in fake.candidateRequests.append(request); return fake.candidateRows },
            loadExistingRows: { _, _ in fake.existingRows },
            sendInvite: { _ in fake.sends += 1; if let error = fake.sendError { throw error } },
            loadOwnerListRows: { _ in fake.ownerListRows },
            loadOwnerMineRows: { _ in fake.ownerMineRows },
            releaseInviteLock: { _ in if let error = fake.releaseError { throw error } }), intents: intents)
    }

    private var vacancyJSON: String { #"{"offerId":900,"topicId":70,"chapterId":7,"status":0,"withdrawReason":"原商家退出","merchantMemberId":11}"# }
    private var candidateJSON: String { #"{"merchantMemberId":42,"chapterId":7,"replacementOfOfferId":900}"# }
    private var landedJSON: String { #"{"id":55,"topicId":70,"chapterId":7,"merchantId":42,"replacementOfOfferId":900,"source":1,"status":0}"# }

    private func readyCoordinator(_ fake: Fake, intents: any ChapterReplacementInvitationIntentStoring = ChapterReplacementInvitationMemoryIntents()) async throws -> ChapterReplacementInvitationCoordinator {
        fake.vacancyRows = [try value(vacancyJSON)]
        fake.candidateRows = [try value(candidateJSON)]
        let coordinator = self.coordinator(fake, intents: intents)
        coordinator.begin(topicID: 70, actorAccountID: 5)
        await coordinator.loadVacancies()
        let vacancy = try XCTUnwrap(coordinator.selectedVacancy ?? coordinator.vacancies.first)
        await coordinator.loadCandidates(for: vacancy, coordinates: nil)
        return coordinator
    }

    func testLostResponseBecomesUnknownNeverResendsAndLateFillVerifies() async throws {
        let fake = Fake()
        let coordinator = try await readyCoordinator(fake)
        XCTAssertNil(fake.candidateRequests.first?.coordinates) // refused location still queried
        fake.sendError = ChapterReplacementInvitationFailure.unknown
        await coordinator.prepare(candidate: coordinator.candidates[0], scope: .currentMember,
                                  merchantAccess: nil, publisherProof: proof())
        await coordinator.confirmSend()
        XCTAssertEqual(fake.sends, 1)
        guard case .unknown = coordinator.phase else { return XCTFail("expected unknown, got \(coordinator.phase)") }
        // Late fill: readback appears only on a later verification pass.
        fake.ownerMineRows = [try value(landedJSON)]
        fake.vacancyRows = [] // vacancy consumed after the invite lands
        await coordinator.verifyUnknown()
        XCTAssertEqual(fake.sends, 1)
        guard case .verified(let verified) = coordinator.phase else { return XCTFail("expected verified, got \(coordinator.phase)") }
        XCTAssertEqual(verified.applicationID, 55)
        XCTAssertTrue(coordinator.vacancies.isEmpty) // vacancy list refreshed after readback
    }

    func testSuccessfulSendVerifiesByExactTupleAndRefreshesVacancies() async throws {
        let fake = Fake()
        let coordinator = try await readyCoordinator(fake)
        fake.ownerListRows = [try value(landedJSON)]
        fake.vacancyRows = []
        await coordinator.prepare(candidate: coordinator.candidates[0], scope: .currentMember,
                                  merchantAccess: nil, publisherProof: proof())
        let loadsBefore = fake.vacancyLoads
        await coordinator.confirmSend()
        XCTAssertEqual(fake.sends, 1)
        guard case .verified = coordinator.phase else { return XCTFail("expected verified, got \(coordinator.phase)") }
        XCTAssertGreaterThan(fake.vacancyLoads, loadsBefore)
    }

    func testTopicOrAccountChangeRetiresFrozenPlan() async throws {
        let fake = Fake()
        let coordinator = try await readyCoordinator(fake)
        await coordinator.prepare(candidate: coordinator.candidates[0], scope: .currentMember,
                                  merchantAccess: nil, publisherProof: proof())
        guard case .reviewing(let plan) = coordinator.phase else { return XCTFail("expected reviewing") }
        coordinator.begin(topicID: 71, actorAccountID: 5)
        XCTAssertThrowsError(try plan.validateCurrent(topicID: 71, actorAccountID: 5)) {
            XCTAssertEqual($0 as? ChapterReplacementInvitationFailure, .staleTopic)
        }
        coordinator.begin(topicID: 70, actorAccountID: 6)
        XCTAssertThrowsError(try plan.validateCurrent(topicID: 70, actorAccountID: 6))
        await coordinator.confirmSend() // retired plan cannot dispatch under the new context
        XCTAssertEqual(fake.sends, 0)
    }

    func testReopenAfterUnknownDoesNotSendAgain() async throws {
        let fake = Fake()
        let intents = ChapterReplacementInvitationMemoryIntents()
        let coordinator = try await readyCoordinator(fake, intents: intents)
        fake.sendError = ChapterReplacementInvitationFailure.unknown
        await coordinator.prepare(candidate: coordinator.candidates[0], scope: .currentMember,
                                  merchantAccess: nil, publisherProof: proof())
        await coordinator.confirmSend()
        XCTAssertEqual(fake.sends, 1)
        let reopened = self.coordinator(fake, intents: intents)
        reopened.begin(topicID: 99, actorAccountID: 9)
        guard case .unknown = reopened.phase else { return XCTFail("expected restored unknown, got \(reopened.phase)") }
        await reopened.confirmSend()
        await reopened.loadVacancies()
        XCTAssertEqual(fake.sends, 1)
        guard case .unknown = reopened.phase else { return XCTFail("lock dropped, got \(reopened.phase)") }
    }

    func testFileIntentSurvivesNewStoreAndCorruptFileStaysLocked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("c9-intent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = Fake()
        let first = try await readyCoordinator(fake, intents: ChapterReplacementInvitationFileIntents(directory: directory))
        fake.sendError = ChapterReplacementInvitationFailure.unknown
        await first.prepare(candidate: first.candidates[0], scope: .currentMember,
                            merchantAccess: nil, publisherProof: proof())
        await first.confirmSend()
        XCTAssertEqual(fake.sends, 1)
        let restarted = self.coordinator(fake, intents: ChapterReplacementInvitationFileIntents(directory: directory))
        restarted.begin(topicID: 1, actorAccountID: 1)
        guard case .unknown = restarted.phase else { return XCTFail("expected file lock, got \(restarted.phase)") }
        await restarted.confirmSend()
        XCTAssertEqual(fake.sends, 1)
        let file = directory.appendingPathComponent("chapter-replacement-intent.json")
        try Data("nope".utf8).write(to: file)
        let blocked = self.coordinator(fake, intents: ChapterReplacementInvitationFileIntents(directory: directory))
        blocked.begin(topicID: 70, actorAccountID: 5)
        XCTAssertEqual(blocked.phase, .failed(.unknown))
        await blocked.loadVacancies()
        await blocked.confirmSend()
        XCTAssertEqual(fake.sends, 1)
        XCTAssertEqual(blocked.phase, .failed(.unknown))
    }

    func testReleaseFailureStaysUnknownAndDoesNotResend() async throws {
        let fake = Fake()
        let intents = ChapterReplacementInvitationMemoryIntents()
        let coordinator = try await readyCoordinator(fake, intents: intents)
        fake.sendError = ChapterReplacementInvitationFailure.unknown
        await coordinator.prepare(candidate: coordinator.candidates[0], scope: .currentMember,
                                  merchantAccess: nil, publisherProof: proof())
        await coordinator.confirmSend()
        fake.ownerMineRows = [try value(landedJSON)]
        fake.releaseError = ChapterReplacementInvitationFailure.unknown
        await coordinator.verifyUnknown()
        XCTAssertEqual(fake.sends, 1)
        guard case .unknown = coordinator.phase else { return XCTFail("expected unknown, got \(coordinator.phase)") }
        XCTAssertNotNil(try intents.load())
    }
}

@MainActor
final class ChapterInviteLockReleaseTests: XCTestCase {
    private struct DeadTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, Int) { throw APIError.notConfigured }
    }

    private func plan(actor: Int = 5, scope: ChapterReplacementInvitationScope = .currentMember) -> ChapterReplacementInvitationPlan {
        let vacancy = ChapterReplacementInvitationVacancy(lockedOfferID: 900, topicID: 70, chapterID: 7)
        let candidate = ChapterReplacementInvitationCandidate(merchantMemberID: 42, chapterID: 7, replacementOfOfferID: 900)
        return ChapterReplacementInvitationPlan(topicID: 70, vacancy: vacancy, candidate: candidate,
                                                scope: scope, actorAccountID: actor, message: nil)
    }

    private func row(scope: String = "cn", account: Int = 5, merchant: Int = 31, target: String) -> MerchantContentPendingRecord {
        MerchantContentPendingRecord(storageScope: scope, accountID: account, merchantID: merchant, target: target, action: "invite", station: nil)
    }

    private func service(session: MerchantContentSession?, journal: MerchantContentMemoryPendingStorage) -> MerchantContentService {
        MerchantContentService(configuration: nil, transport: DeadTransport(), currentSession: { session }, journal: journal)
    }

    func testReadbackClearsOnlyTheMatchingInviteRow() async throws {
        let session = try MerchantContentSession(accountID: 5, epoch: 1, storageScope: "cn", token: "token")
        let journal = MerchantContentMemoryPendingStorage()
        let match = row(target: "invite:7:42:900:SELF:1")
        let otherTuple = row(target: "invite:8:42:900:SELF:0")
        try journal.insert(match); try journal.insert(otherTuple)
        let content = service(session: session, journal: journal)
        try content.releaseChapterReplacementInviteLock(plan())
        let left = try journal.records()
        XCTAssertFalse(left.contains(match))
        XCTAssertTrue(left.contains(otherTuple))
        try content.releaseChapterReplacementInviteLock(plan())
        let otherAccountJournal = MerchantContentMemoryPendingStorage()
        let otherAccount = row(account: 6, target: "invite:7:42:900:SELF:0")
        try otherAccountJournal.insert(otherAccount)
        XCTAssertThrowsError(try service(session: session, journal: otherAccountJournal).releaseChapterReplacementInviteLock(plan()))
        XCTAssertEqual(try otherAccountJournal.records(), [otherAccount])

        let ambiguous = MerchantContentMemoryPendingStorage()
        try ambiguous.insert(row(target: "invite:7:42:900:SELF:0"))
        try ambiguous.insert(row(merchant: 32, target: "invite:7:42:900:SELF:1"))
        XCTAssertThrowsError(try service(session: session, journal: ambiguous).releaseChapterReplacementInviteLock(plan()))
        XCTAssertEqual(try ambiguous.records().count, 2)

        let kept = MerchantContentMemoryPendingStorage()
        let foreign = row(scope: "us", target: "invite:7:42:900:SELF:0")
        try kept.insert(foreign)
        XCTAssertThrowsError(try service(session: session, journal: kept).releaseChapterReplacementInviteLock(plan()))
        XCTAssertThrowsError(try service(session: nil, journal: kept).releaseChapterReplacementInviteLock(plan()))
        let other = try MerchantContentSession(accountID: 6, epoch: 1, storageScope: "cn", token: "token")
        XCTAssertThrowsError(try service(session: other, journal: kept).releaseChapterReplacementInviteLock(plan()))
        XCTAssertEqual(try kept.records(), [foreign])
    }
}

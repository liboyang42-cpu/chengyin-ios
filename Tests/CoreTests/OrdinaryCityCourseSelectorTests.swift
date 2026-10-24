import XCTest
@testable import QuestifyCore

final class OrdinaryCityCourseSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_766_232_000) // 2025-12-20T10:00:00Z
    private func catalog() throws -> [OrdinaryCityCourseRecord] {
        let json = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2",\
        "participationMode":"TEAM","requiredClubIds":[11,22],"matchmakingStatus":"CANCELLED"}]
        """
        return try OrdinaryCityCourseSelector.decodeCatalog(Data(json.utf8))
    }
    private func clubs(_ member: Int = 701) -> [TeamClubMembership] {
        [TeamClubMembership(clubID: 11, memberID: member, status: "ACTIVE")!,
         TeamClubMembership(clubID: 22, memberID: member, status: "ACTIVE")!]
    }
    private func team(_ member: Int = 701) -> TeamRoster {
        TeamRoster(teamID: 501, memberIDs: [member, 702], formedBy: "INVITE", affiliatedClubIDs: [11, 22])!
    }
    func testFirstJourneyFreezesRuleVersionForFinishAndDispute() throws {
        let catalog = try catalog()
        let start = try XCTUnwrap(OrdinaryCityCourseSelector.prepareStart(
            courseID: 1001, catalog: catalog, actorMemberID: 701, actorClubs: clubs(), team: team(), now: now))
        XCTAssertEqual(start.selection.courseID, 1001)
        XCTAssertEqual(start.selection.cityTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(start.safety.versionID, "safety-v2")
        XCTAssertEqual(start.safety.cityCivilDate, "2025-12-20")
        XCTAssertTrue(start.eligibility.isEligible)
        XCTAssertEqual(start.eligibility.reasonCode, "TEAM_ELIGIBLE")
        XCTAssertEqual(start.payload.frozenRuleVersionID, "rule-v3")
        XCTAssertEqual(start.payload.resultVersionID, start.payload.frozenRuleVersionID)
        XCTAssertEqual(start.payload.safetyVersionID, "safety-v2")
        let finish = try XCTUnwrap(EventScoreVersionProjection.finish(start: start.payload, resultVersionID: "rule-v3"))
        let dispute = try XCTUnwrap(EventScoreVersionProjection.dispute(start: start.payload, resultVersionID: "rule-v3"))
        XCTAssertEqual(finish.kind, .finish)
        XCTAssertEqual(dispute.kind, .dispute)
        XCTAssertEqual(finish.resultVersionID, start.payload.resultVersionID)
        XCTAssertEqual(dispute.resultVersionID, start.payload.resultVersionID)
        XCTAssertNil(EventScoreVersionProjection.finish(start: start.payload, resultVersionID: "rule-v4"))
        XCTAssertNil(EventScoreVersionProjection.dispute(start: start.payload, resultVersionID: "rule-v4"))
        XCTAssertTrue(EventScoreVersionProjection.retainsFrozenRule(start: start.payload, laterPublishedRuleVersionID: "rule-v4"))
    }
    func testSafetyCivilDateUsesCityTimezoneNotUTCInstant() throws {
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: try catalog()))
        let shanghai = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        XCTAssertEqual(shanghai.cityCivilDate, "2025-12-20")
        let dusk = Date(timeIntervalSince1970: 1_766_217_600) // 2025-12-20T06:00:00Z == 14:00 Shanghai, 22:00 prior day in US/Hawaii
        let lateShanghai = try XCTUnwrap(OrienteeringSafetyVersion.cityCivilDate(
            now: dusk, timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))))
        let hawaii = try XCTUnwrap(OrienteeringSafetyVersion.cityCivilDate(
            now: dusk, timeZone: XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))))
        XCTAssertEqual(lateShanghai, "2025-12-20")
        XCTAssertEqual(hawaii, "2025-12-19")
    }
    func testUnpublishedFreeExploreGrowthAndGPSAreNotSelectable() throws {
        XCTAssertNotNil(OrdinaryCityCourseSelector.select(courseID: 1001, from: try catalog()))
        let unpublished = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"DRAFT",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(unpublished.utf8))))
        let notPublished = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"UNPUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(notPublished.utf8))))
        let free = """
        [{"courseId":1001,"topicId":2001,"productType":2,"publicationStatus":"PUBLISHED",\
        "kind":"FREE_EXPLORATION","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"SOLO"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(free.utf8))))
        let growth = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"GROWTH_PERSONAL_RANK","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(growth.utf8))))
        let gps = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM",\
        "latitude":31.2,"longitude":121.5,"accuracyMeters":5}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(gps.utf8))))
        let matching = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM",\
        "matchmakingStatus":"MATCHING"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(matching.utf8))))
    }
    func testMissingCityTimezoneAndBlankVersionsFailClosed() throws {
        let noZone = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Not/AZone",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(noZone.utf8))))
        let blank = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(blank.utf8))))
    }
    func testSafetyMismatchCannotFreezeStart() throws {
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: try catalog()))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        let other = OrdinaryCityCourseSelection(
            courseID: selection.courseID, topicID: selection.topicID,
            cityTimeZoneIdentifier: selection.cityTimeZoneIdentifier,
            publishedRuleVersionID: selection.publishedRuleVersionID,
            safetyVersionID: "safety-other", participationMode: selection.participationMode,
            requiredClubIDs: selection.requiredClubIDs)
        XCTAssertFalse(safety.matches(other))
        XCTAssertNil(EventScoreVersionProjection.freeze(selection: other, safety: safety))
    }
    func testPrepareStartRequiresEligibleTeam() throws {
        let catalog = try catalog()
        XCTAssertNil(OrdinaryCityCourseSelector.prepareStart(
            courseID: 1001, catalog: catalog, actorMemberID: 701, actorClubs: clubs(), team: nil, now: now))
        XCTAssertNil(OrdinaryCityCourseSelector.prepareStart(
            courseID: 1002, catalog: catalog, actorMemberID: 701, actorClubs: clubs(), team: team(), now: now))
    }
    func testGPSEvidenceAndGrowthLeaderboardStayRejected() {
        XCTAssertTrue(EventScoreVersionProjection.rejectsGPSEvidence(kind: "GPS", fingerprint: "task:31"))
        XCTAssertTrue(EventScoreVersionProjection.rejectsGPSEvidence(
            kind: "SCAN", fingerprint: #"{"latitude":31.2,"longitude":121.5}"#))
        XCTAssertFalse(EventScoreVersionProjection.rejectsGPSEvidence(kind: "SCAN", fingerprint: "task:31:scan"))
        XCTAssertFalse(EventScoreVersionProjection.growthLeaderboardSubstitutesEventScore(1))
        XCTAssertFalse(EventScoreVersionProjection.growthLeaderboardSubstitutesEventScore(nil))
        XCTAssertFalse(TeamClubEligibilityProjection.growthRankGrantsEligibility(99))
        XCTAssertFalse(OrdinaryCitySourceInventory.vol21Present)
        XCTAssertEqual(OrdinaryCitySourceInventory.leftovers.contains("WAITING_SOURCE"), true)
    }
    func testOtherTeamRegisterFinishRequestDoesNotRewriteOriginalFreezeFinishRequestID() throws {
        let catalog = try catalog()
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: catalog))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        var session = OrdinaryCityOrienteeringOriginalSession()
        let originalTeam = try XCTUnwrap(session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: "reg-isol-01"))
        XCTAssertEqual(originalTeam.originalRequestID, "reg-isol-01")
        XCTAssertEqual(originalTeam.outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(originalTeam.mintedNewRequest, false)
        let frozen = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: "start-iso1")
        XCTAssertEqual(frozen.originalRequestID, "start-iso1")
        XCTAssertEqual(frozen.outcome, .running)
        let start = try XCTUnwrap(frozen.start)
        XCTAssertEqual(start.originalRequestID, "start-iso1")
        let finished = session.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "fin-isol-01")
        XCTAssertEqual(finished.originalRequestID, "fin-isol-01")
        XCTAssertEqual(finished.outcome, .finished)
        XCTAssertEqual(finished.terminal?.kind, .finish)
        let rewriteRegister = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(),
            team: TeamRoster(teamID: 501, memberIDs: [701, 702, 703], formedBy: "INVITE",
                             affiliatedClubIDs: [11, 22]),
            originalRequestID: "reg-isol-01")
        XCTAssertEqual(rewriteRegister.outcome, EventScoreOriginalOutcome.idempotencyConflict.rawValue)
        XCTAssertEqual(rewriteRegister.originalRequestID, "reg-isol-01")
        XCTAssertEqual(rewriteRegister.registration?.memberIDs, [701, 702])
        let switchedTeam = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(),
            team: TeamRoster(teamID: 502, memberIDs: [701, 702, 703], formedBy: "INVITE",
                             affiliatedClubIDs: [11, 22]),
            originalRequestID: "reg-isol-02")
        XCTAssertEqual(switchedTeam.originalRequestID, "reg-isol-02")
        XCTAssertNotEqual(switchedTeam.originalRequestID, originalTeam.originalRequestID)
        let switchedStart = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: "start-iso2")
        let otherFinish = session.finish(
            start: try XCTUnwrap(switchedStart.start), resultVersionID: "rule-v3",
            originalRequestID: "fin-isol-02")
        XCTAssertEqual(otherFinish.originalRequestID, "fin-isol-02")
        let steal = session.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "fin-isol-02")
        XCTAssertEqual(steal.outcome, .idempotencyConflict)
        XCTAssertEqual(steal.originalRequestID, "fin-isol-01")
        let minted = session.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "fin-new-01")
        XCTAssertEqual(minted.outcome, .idempotencyConflict)
        XCTAssertEqual(minted.originalRequestID, "fin-isol-01")
        let originalReadback = session.scores.readback("fin-isol-01")
        XCTAssertEqual(originalReadback.originalRequestID, "fin-isol-01")
        XCTAssertEqual(originalReadback.outcome, .finished)
        XCTAssertEqual(session.teams.readback("reg-isol-01").originalRequestID, "reg-isol-01")
        XCTAssertEqual(session.teams.readback("reg-isol-01").registration?.memberIDs, [701, 702])
    }
    func testInProcessRecoverKeepsOriginalFinishedAndNotFoundUnknown() throws {
        let catalog = try catalog()
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: catalog))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        var session = OrdinaryCityOrienteeringOriginalSession()
        _ = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: "reg-isol-01")
        let frozen = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: "start-iso1")
        let start = try XCTUnwrap(frozen.start)
        let finished = session.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "fin-isol-01")
        XCTAssertEqual(finished.outcome, .finished)
        let restarted = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: "start-iso1")
        XCTAssertEqual(restarted.originalRequestID, "start-iso1")
        XCTAssertEqual(restarted.outcome, .finished)
        XCTAssertEqual(restarted.terminal?.originalRequestID, "fin-isol-01")
        XCTAssertEqual(restarted.mintedNewRequest, false)
        let recoveredFinish = session.recoverUnknown(originalRequestID: "fin-isol-01")
        XCTAssertEqual(recoveredFinish.originalRequestID, "fin-isol-01")
        XCTAssertEqual(recoveredFinish.outcome, .finished)
        XCTAssertEqual(recoveredFinish.mintedNewRequest, false)
        let originalRecover = session.recoverOriginal(originalRequestID: "fin-isol-01")
        XCTAssertEqual(originalRecover.outcome, .finished)
        let missing = session.recoverUnknown(originalRequestID: "fin-unknow")
        XCTAssertEqual(missing.originalRequestID, "fin-unknow")
        XCTAssertEqual(missing.outcome, .notFound)
        XCTAssertEqual(missing.mintedNewRequest, false)
        XCTAssertNil(missing.start)
        XCTAssertNil(missing.terminal)
        XCTAssertEqual(session.teams.recoverUnknown(originalRequestID: "reg-unknow").outcome,
                       EventScoreOriginalOutcome.notFound.rawValue)
        XCTAssertEqual(session.scores.readback("fin-isol-01").outcome, .finished)
        XCTAssertEqual(session.teams.readback("reg-isol-01").originalRequestID, "reg-isol-01")
    }
    func testMissingBlankRequestIDStaysOptionalNoneOrTypedNotFoundNeverEmptyString() throws {
        let catalog = try catalog()
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: catalog))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        var session = OrdinaryCityOrienteeringOriginalSession()
        XCTAssertNil(EventScoreRequestIdentity.parse(nil))
        XCTAssertNil(EventScoreRequestIdentity.parse(""))
        XCTAssertNil(EventScoreRequestIdentity.parse("   "))
        let blankRegister = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: nil)
        XCTAssertNil(blankRegister.originalRequestID)
        XCTAssertEqual(blankRegister.outcome, EventScoreOriginalOutcome.invalidArgument.rawValue)
        XCTAssertEqual(blankRegister.mintedNewRequest, false)
        let emptyRegister = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: "")
        XCTAssertNil(emptyRegister.originalRequestID)
        XCTAssertEqual(emptyRegister.outcome, EventScoreOriginalOutcome.invalidArgument.rawValue)
        let blankStart = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: nil)
        XCTAssertNil(blankStart.originalRequestID)
        XCTAssertEqual(blankStart.outcome, .invalidArgument)
        let original = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: "reg-isol-01")
        XCTAssertEqual(original.originalRequestID, "reg-isol-01")
        let frozen = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: "start-iso1")
        let start = try XCTUnwrap(frozen.start)
        XCTAssertNil(session.finish(start: start, resultVersionID: "rule-v3", originalRequestID: nil).originalRequestID)
        XCTAssertEqual(
            session.finish(start: start, resultVersionID: "rule-v3", originalRequestID: "").outcome,
            .invalidArgument)
        let finished = session.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "fin-isol-01")
        XCTAssertEqual(finished.originalRequestID, "fin-isol-01")
        XCTAssertNotEqual(finished.originalRequestID, Optional.some(""))
        let missingRead = session.recoverUnknown(originalRequestID: nil)
        XCTAssertNil(missingRead.originalRequestID)
        XCTAssertEqual(missingRead.outcome, .notFound)
        XCTAssertEqual(missingRead.mintedNewRequest, false)
        let blankRead = session.recoverUnknown(originalRequestID: "")
        XCTAssertNil(blankRead.originalRequestID)
        XCTAssertEqual(blankRead.outcome, .notFound)
        XCTAssertNil(session.teams.readback(nil).originalRequestID)
        XCTAssertEqual(session.teams.readback("").outcome, EventScoreOriginalOutcome.notFound.rawValue)
        let staticFreeze = try XCTUnwrap(EventScoreVersionProjection.freeze(selection: selection, safety: safety))
        XCTAssertNil(staticFreeze.originalRequestID)
        XCTAssertEqual(session.scores.readback("fin-isol-01").originalRequestID, "fin-isol-01")
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenUniqueWriteApplies() throws {
        let catalog = try catalog()
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: catalog))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        var session = OrdinaryCityOrienteeringOriginalSession()
        _ = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: "reg-isol-01")
        let frozen = session.freezeStart(
            selection: selection, safety: safety, originalRequestID: "start-iso1")
        let start = try XCTUnwrap(frozen.start)

        let blank = session.recoverOriginal(originalRequestID: nil)
        XCTAssertNil(blank.originalRequestID)
        XCTAssertEqual(blank.outcome, .notFound)
        XCTAssertEqual(blank.mintedNewRequest, false)
        let neverFinish = session.recoverOriginal(originalRequestID: "fin-orig-unk")
        XCTAssertEqual(neverFinish.originalRequestID, "fin-orig-unk")
        XCTAssertEqual(neverFinish.outcome, .notFound)
        XCTAssertEqual(neverFinish.mintedNewRequest, false)
        XCTAssertNil(neverFinish.start)
        XCTAssertNil(neverFinish.terminal)
        XCTAssertEqual(session.scores.readback("fin-orig-unk").outcome, .notFound)

        let firstFinish = session.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "fin-orig-unk")
        XCTAssertEqual(firstFinish.originalRequestID, "fin-orig-unk")
        XCTAssertEqual(firstFinish.outcome, .finished)
        XCTAssertEqual(firstFinish.mintedNewRequest, false)
        let recoveredFinish = session.recoverOriginal(originalRequestID: "fin-orig-unk")
        XCTAssertEqual(recoveredFinish.originalRequestID, "fin-orig-unk")
        XCTAssertEqual(recoveredFinish.outcome, .finished)
        XCTAssertEqual(session.scores.readback("fin-orig-unk").outcome, .finished)

        let neverReg = session.teams.recoverOriginal(originalRequestID: "reg-orig-unk")
        XCTAssertEqual(neverReg.originalRequestID, "reg-orig-unk")
        XCTAssertEqual(neverReg.outcome, EventScoreOriginalOutcome.notFound.rawValue)
        XCTAssertNil(neverReg.registration)
        XCTAssertEqual(session.teams.readback("reg-orig-unk").outcome, EventScoreOriginalOutcome.notFound.rawValue)
        let firstUnknownReg = session.registerTEAM(
            selection: selection, actorMemberID: 701, actorClubs: clubs(), team: team(),
            originalRequestID: "reg-orig-unk")
        XCTAssertEqual(firstUnknownReg.originalRequestID, "reg-orig-unk")
        XCTAssertEqual(firstUnknownReg.outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(session.teams.recoverOriginal(originalRequestID: "reg-orig-unk").outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(session.teams.readback("reg-isol-01").originalRequestID, "reg-isol-01")
    }
    func testLedgerRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueFinishApplies() throws {
        let catalog = try catalog()
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: catalog))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        var ledger = EventScoreOriginalLedger()
        let blank = ledger.recoverOriginal(originalRequestID: nil)
        XCTAssertNil(blank.originalRequestID)
        XCTAssertEqual(blank.outcome, .notFound)
        XCTAssertEqual(blank.mintedNewRequest, false)
        let neverFinish = ledger.recoverOriginal(originalRequestID: "c04-fin-class")
        XCTAssertEqual(neverFinish.originalRequestID, "c04-fin-class")
        XCTAssertEqual(neverFinish.outcome, .notFound)
        XCTAssertEqual(neverFinish.mintedNewRequest, false)
        XCTAssertNil(neverFinish.start)
        XCTAssertNil(neverFinish.terminal)
        XCTAssertEqual(ledger.readback("c04-fin-class").outcome, .notFound)
        XCTAssertNil(ledger.readback("c04-fin-class").start)

        let frozen = ledger.freeze(
            selection: selection, safety: safety, originalRequestID: "c04-start-cl")
        XCTAssertEqual(frozen.outcome, .running)
        let start = try XCTUnwrap(frozen.start)
        let firstFinish = ledger.finish(
            start: start, resultVersionID: "rule-v3", originalRequestID: "c04-fin-class")
        XCTAssertEqual(firstFinish.originalRequestID, "c04-fin-class")
        XCTAssertEqual(firstFinish.outcome, .finished)
        XCTAssertEqual(firstFinish.mintedNewRequest, false)
        XCTAssertEqual(ledger.recoverOriginal(originalRequestID: "c04-fin-class").outcome, .finished)
        XCTAssertEqual(ledger.readback("c04-fin-class").outcome, .finished)
        XCTAssertEqual(ledger.recoverOriginal(originalRequestID: "c04-fin-never").outcome, .notFound)
        XCTAssertEqual(ledger.readback("c04-fin-never").outcome, .notFound)
    }
}

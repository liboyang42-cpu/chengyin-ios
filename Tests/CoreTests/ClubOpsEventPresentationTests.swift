import XCTest
@testable import QuestifyCore

final class ClubOpsEventPresentationTests: XCTestCase {
    private func permissions(_ list: [String], events: [ClubGovernanceValue] = [], scope: ClubGovernanceScope) throws -> ClubGovernancePermissions {
        try .init(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]),
                                  "permissions": .array(list.map(ClubGovernanceValue.string)), "eventAccesses": .array(events)]), scope: scope)
    }
    private let zh = Locale(identifier: "zh-Hans"), en = Locale(identifier: "en_US")

    func testSectionOrderFollowsMiniForManagerWithActivity() throws {
        let scope = ClubGovernanceScope(clubID: 81, topicID: 91, activityID: 101)
        let value = ClubOpsEventAccess(permissions: try permissions(["club:activity:manage", "club:event:checkin"], scope: scope), scope: scope)
        XCTAssertEqual(value.sections, [.occurrence, .roster, .series, .recurrence, .capacity])
        XCTAssertFalse(value.rosterHiddenForManager); XCTAssertTrue(value.permitted)
    }
    func testManagerWithoutCheckinSeesHiddenRosterNotice() throws {
        let scope = ClubGovernanceScope(clubID: 81, activityID: 101)
        let value = ClubOpsEventAccess(permissions: try permissions(["club:activity:manage"], scope: scope), scope: scope)
        XCTAssertEqual(value.sections, [.occurrence, .series, .recurrence, .capacity]); XCTAssertTrue(value.rosterHiddenForManager)
    }
    func testCheckinNeedsActivityAndDelegatedCheckinIsRosterOnly() throws {
        let club = ClubGovernanceScope(clubID: 81)
        XCTAssertFalse(ClubOpsEventAccess(permissions: try permissions(["club:event:checkin"], scope: club), scope: club).permitted)
        let scope = ClubGovernanceScope(clubID: 81, activityID: 101)
        let event: ClubGovernanceValue = .object(["activityId": .integer(101), "topicId": .integer(91), "roleCodes": .array([.string("EVENT_CHECKIN")]), "permissions": .array([.string("club:event:checkin")])])
        let value = ClubOpsEventAccess(permissions: try permissions([], events: [event], scope: scope), scope: scope)
        XCTAssertEqual(value.sections, [.roster]); XCTAssertFalse(value.canManage)
        XCTAssertFalse(ClubOpsEventAccess(permissions: nil, scope: scope).permitted)
    }
    func testFocusTopicMovesFirstWithoutHidingOthers() {
        let rows: [ClubGovernanceValue] = [.object(["id": .integer(1)]), .object(["id": .integer(2)]), .object(["id": .integer(3)])]
        XCTAssertEqual(ClubOpsEventAccess.focusFirst(rows, topicID: 2).map { $0["id"].int }, [2, 1, 3])
        XCTAssertEqual(ClubOpsEventAccess.focusFirst(rows, topicID: nil), rows)
        XCTAssertEqual(ClubOpsEventAccess.focusFirst(rows, topicID: 9), rows)
    }
    func testOccurrenceDateUsesShanghaiCalendarAndWeekday() {
        XCTAssertEqual(ClubOpsEventClock.occurrenceText(.string("2026-09-28 09:00:00"), locale: zh), "9月28日 周一 09:00")
        XCTAssertEqual(ClubOpsEventClock.occurrenceText(.string("2026-09-27T16:30:00Z"), locale: zh), "9月28日 周一 00:30")
        XCTAssertNil(ClubOpsEventClock.occurrenceText(.string("unknown"), locale: zh))
        let english = ClubOpsEventClock.occurrenceText(.string("2026-09-28 09:00"), locale: en) ?? ""
        XCTAssertTrue(english.contains("28") && english.contains("09:00"), english)
    }
    func testCorrectionWindowRangeAndSingleBound() {
        XCTAssertEqual(ClubOpsEventClock.correctionRange(start: "2026-10-08 09:00:00", end: "2026-10-10 18:00:00", locale: zh), "10月8日 09:00 – 10月10日 18:00")
        XCTAssertEqual(ClubOpsEventClock.correctionRange(start: nil, end: "2026-10-10 18:00:00", locale: zh), "10月10日 18:00")
        XCTAssertNil(ClubOpsEventClock.correctionRange(start: "bad", end: nil, locale: zh))
    }
    func testArrivedIsDerivedFromBucket() {
        XCTAssertEqual(ClubOpsEventAttendance.arrivedTarget(.registered), true)
        XCTAssertEqual(ClubOpsEventAttendance.arrivedTarget(.noShow), true)
        XCTAssertEqual(ClubOpsEventAttendance.arrivedTarget(.arrived), false)
        XCTAssertNil(ClubOpsEventAttendance.arrivedTarget(.waitlist))
    }
    private func row(cancelled: Bool = false, editable: Bool? = nil, lock: String? = nil, signups: Int? = nil, refunded: Int? = nil) -> ClubSeriesOccurrenceRow {
        .init(id: 0, occurrenceID: 1, activityID: 2, dateText: nil, dateIsParsed: false, cancelled: cancelled, editable: editable,
              lockReason: lock, signupCount: signups, refundedCount: refunded)
    }
    func testOccurrenceCopyNeverReadsUnknownAsZeroOrEditable() {
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(cancelled: true, refunded: 3)), .init(row: row(cancelled: true, refunded: 3)))
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(cancelled: true, refunded: 3)).meta, .refunded(3))
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(cancelled: true)).meta, .cancelled)
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(cancelled: true)).badge, .cancelled)
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row()).meta, .signupsPending)
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row()).badge, .locked)
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(editable: false, lock: "已有报名", signups: 0)).meta, .noSignups)
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(editable: false, lock: "已有报名", signups: 0)).badge, .lockReason("已有报名"))
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(editable: nil, signups: 4)).meta, .signups(4, locked: true))
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(editable: true, signups: 4)).meta, .signups(4, locked: false))
        XCTAssertEqual(ClubOpsEventOccurrenceCopy(row: row(editable: true, signups: 4)).badge, .editable)
    }
    private func series(_ id: Int, topic: Int, kind: String = "CUSTOM_DATES", dates: [String] = []) -> ClubGovernanceValue {
        .object(["id": .integer(id), "topicId": .integer(topic), "recurrenceType": .string(kind), "waitlistEnabled": .bool(true),
                 "futureDates": .array(dates.map(ClubGovernanceValue.string))])
    }
    func testSeriesLabelsOnlyDeepenCollidingRows() {
        let names = [7: "探店日", 8: "探店日", 9: "夜跑"]
        let plain = ClubOpsEventSeriesList(value: .array([series(1, topic: 7, kind: "WEEKLY"), series(2, topic: 8), series(3, topic: 9)]), topicNames: names)
        XCTAssertTrue(plain.rows.allSatisfy { $0.suffix.isEmpty })
        let dated = ClubOpsEventSeriesList(value: .array([series(1, topic: 7, dates: ["2026-10-09", "2026-10-02"]), series(2, topic: 8, dates: ["2026-10-03"]), series(3, topic: 9)]), topicNames: names)
        XCTAssertEqual(dated.rows.map(\.suffix), [[.firstDate(month: 10, day: 2)], [.firstDate(month: 10, day: 3)], []])
        let undated = ClubOpsEventSeriesList(value: .array([series(1, topic: 7), series(2, topic: 8)]), topicNames: names)
        XCTAssertEqual(undated.rows.map(\.suffix), [[.topic(7)], [.topic(8)]])
        let sameTopic = ClubOpsEventSeriesList(value: .array([series(1, topic: 7), series(2, topic: 7)]), topicNames: names)
        XCTAssertEqual(sameTopic.rows.map(\.suffix), [[.topic(7), .series(1)], [.topic(7), .series(2)]])
        XCTAssertNil(ClubOpsEventSeriesList(value: .array([series(4, topic: 5)])).rows.first?.topicName)
    }
    private func status(_ status: String, cancelled: Bool, publish: Int, reason: String? = nil, activity: Int = 101) -> ClubGovernanceValue {
        .object(["activityId": .integer(activity), "occurrenceStatus": .string(status), "activityCancelled": .bool(cancelled),
                 "publishStatus": .integer(publish), "cancelReason": reason.map(ClubGovernanceValue.string) ?? .null])
    }
    func testCancellationStateFailsClosedOnContradiction() {
        XCTAssertEqual(ClubOpsEventCancellation.state(status("ACTIVE", cancelled: false, publish: 1), activityID: 101), .active)
        XCTAssertEqual(ClubOpsEventCancellation.state(status("CANCELLED", cancelled: true, publish: 0, reason: " 天气 "), activityID: 101), .cancelled(reason: "天气"))
        XCTAssertEqual(ClubOpsEventCancellation.state(status("CANCELLED", cancelled: true, publish: 0, reason: " "), activityID: 101), .cancelled(reason: nil))
        XCTAssertNil(ClubOpsEventCancellation.state(status("CANCELLED", cancelled: false, publish: 0), activityID: 101))
        XCTAssertNil(ClubOpsEventCancellation.state(status("ACTIVE", cancelled: false, publish: 0), activityID: 101))
        XCTAssertNil(ClubOpsEventCancellation.state(status("ACTIVE", cancelled: false, publish: 1, activity: 102), activityID: 101))
        XCTAssertNil(ClubOpsEventCancellation.state(status("PENDING", cancelled: false, publish: 1), activityID: 101))
    }
    func testRefundAndNotificationSummaryMapping() {
        let cases: [(String?, ClubOpsEventRefundSummary)] = [("NOT_REQUIRED", .notRequired), ("MANUAL_REVIEW_REQUIRED", .manualReview),
            ("ACCEPTED_WITH_MANUAL_REVIEW", .acceptedWithManualReview), ("ACCEPTED", .accepted), ("REFUND_REQUESTED", .accepted),
            ("ALREADY_ACCEPTED", .accepted), ("SOMETHING_NEW", .pending), (nil, .pending)]
        for (raw, expected) in cases {
            XCTAssertEqual(ClubOpsEventCancellation.refund(.object(["refundStatus": raw.map(ClubGovernanceValue.string) ?? .null])), expected)
        }
        XCTAssertEqual(ClubOpsEventCancellation.notifications(.object(["registeredNotificationStatus": .string("NOT_REQUIRED"), "waitlistNotificationStatus": .string("NOT_REQUIRED")])), .notRequired)
        XCTAssertEqual(ClubOpsEventCancellation.notifications(.object(["registeredNotificationStatus": .string("NOT_REQUIRED")])), .queued)
    }
    func testFieldSpecificRangesMirrorCommand() {
        XCTAssertFalse(ClubOpsEventInput.capacityInvalid("")); XCTAssertFalse(ClubOpsEventInput.capacityInvalid(" 10000 "))
        XCTAssertTrue(ClubOpsEventInput.capacityInvalid("0")); XCTAssertTrue(ClubOpsEventInput.capacityInvalid("10001")); XCTAssertTrue(ClubOpsEventInput.capacityInvalid("1.5"))
        XCTAssertFalse(ClubOpsEventInput.offerInvalid("5")); XCTAssertFalse(ClubOpsEventInput.offerInvalid("1440"))
        XCTAssertTrue(ClubOpsEventInput.offerInvalid("4")); XCTAssertTrue(ClubOpsEventInput.offerInvalid("")); XCTAssertTrue(ClubOpsEventInput.offerInvalid("1441"))
        XCTAssertTrue(ClubOpsEventInput.cancelReasonInvalid(" a ")); XCTAssertFalse(ClubOpsEventInput.cancelReasonInvalid("下雨"))
        XCTAssertTrue(ClubOpsEventInput.cancelReasonInvalid(String(repeating: "x", count: 256)))
        XCTAssertTrue(ClubOpsEventInput.correctionReasonInvalid("x")); XCTAssertFalse(ClubOpsEventInput.correctionReasonInvalid("迟到"))
    }
    func testCreateDefaultsAndOwnerDefaultLeadSendsExplicitNull() throws {
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: .init(clubID: 81, topicID: 91))
        XCTAssertEqual(draft.flags["waitlistEnabled"], true); XCTAssertEqual(draft.text["occurrenceCount"], "4")
        draft.text["startDate"] = "2026-10-08"; draft.text["recurrenceType"] = "WEEKLY"
        XCTAssertThrowsError(try draft.command())
        draft.text["defaultLeadMemberId"] = ClubGovernanceFormDraft.ownerDefaultLead
        let command = try draft.command()
        XCTAssertEqual(command.fields["defaultLeadMemberId"], .null); XCTAssertEqual(command.fields["occurrenceCount"], .integer(4))
        draft.text["recurrenceType"] = "ONCE"; XCTAssertEqual(try draft.command().fields["occurrenceCount"], .integer(1))
        var update = ClubGovernanceFormDraft(operation: .updateSeries, scope: .init(clubID: 81, topicID: 91, seriesID: 111),
                                             seed: ClubGovernanceFixtures.value(.seriesDetail).object ?? [:])
        update.text["startDate"] = "2026-10-08"; update.text["startTime"] = "09:00"
        update.text["defaultLeadMemberId"] = ClubGovernanceFormDraft.ownerDefaultLead
        XCTAssertThrowsError(try update.command())
        XCTAssertThrowsError(try ClubGovernanceCommand(operation: .updateSeries, scope: .init(clubID: 81, topicID: 91, seriesID: 111),
            values: (try ClubGovernanceFixtures.command(.updateSeries).fields).filter { !["clubId", "topicId", "seriesId"].contains($0.key) }
                .merging(["defaultLeadMemberId": .null]) { _, new in new }))
    }
    func testCorrectionArrivedIsAnchoredNotAToggle() throws {
        let scope = ClubGovernanceScope(clubID: 81, activityID: 101, memberID: 704)
        var draft = ClubGovernanceFormDraft(operation: .correctAttendance, scope: scope, seed: ["expectedVersion": .integer(2), "arrived": .bool(false)])
        XCTAssertNil(draft.flags["arrived"]); XCTAssertEqual(draft.anchors["arrived"], .bool(false))
        draft.text["reason"] = "更正"
        XCTAssertEqual(try draft.command().fields["arrived"], .bool(false))
        var missing = ClubGovernanceFormDraft(operation: .correctAttendance, scope: scope, seed: ["expectedVersion": .integer(2)])
        missing.text["reason"] = "更正"
        XCTAssertThrowsError(try missing.command())
    }
    @MainActor func testOwnerDefaultProofRequiresAnOwnerRow() async throws {
        let access = ClubGovernanceFixtureAccess(), coordinator = ClubGovernanceCoordinator(access: access)
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: ClubGovernanceFixtures.scope)
        draft.text["startDate"] = "2099-10-08"; draft.text["defaultLeadMemberId"] = ClubGovernanceFormDraft.ownerDefaultLead
        let review = try await coordinator.prepare(draft.command())
        XCTAssertEqual(review.command.fields["defaultLeadMemberId"], .null)
        coordinator.cancelReview()
        access.overrideValue[.members] = ClubGovernanceFixtures.json(#"[{"memberId":704,"nickname":"Fixture member","isOwner":false,"role":0}]"#)
        do { _ = try await coordinator.prepare(draft.command()); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .targetChanged) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testTopicNamesComeOnlyFromSameClubEventTopicsRead() throws {
        let scope = ClubGovernanceScope(clubID: 81)
        let value: ClubGovernanceValue = .array([.object(["id": .integer(7), "name": .string(" 夜跑 ")]), .object(["id": .integer(8), "name": .string("  ")]),
                                                 .object(["id": .integer(9)]), .object(["id": .integer(7), "name": .string("Duplicate")])])
        let topics = ClubGovernanceSnapshot(operation: .eventTopics, scope: scope, permissions: nil, value: value)
        XCTAssertEqual(ClubOpsEventTopicNames.names(topics, clubID: 81), [7: "夜跑"])
        XCTAssertEqual(ClubOpsEventTopicNames.names(topics, clubID: 82), [:])
        XCTAssertEqual(ClubOpsEventTopicNames.names(nil, clubID: 81), [:])
        XCTAssertEqual(ClubOpsEventTopicNames.names(.init(operation: .topics, scope: scope, permissions: nil, value: value), clubID: 81), [:])
        let rows = ClubOpsEventSeriesList(value: .array([.object(["id": .integer(1), "topicId": .integer(7), "recurrenceType": .string("WEEKLY")]),
                                                         .object(["id": .integer(2), "topicId": .integer(8), "recurrenceType": .string("WEEKLY")])]),
                                          topicNames: ClubOpsEventTopicNames.names(topics, clubID: 81)).rows
        XCTAssertEqual(rows.map(\.topicName), ["夜跑", nil]); XCTAssertEqual(rows.map(\.suffix), [[], []])
    }
    func testOnlyDefiniteUpdateSeriesConflictQualifiesForRefresh() {
        XCTAssertTrue(ClubOpsEventSeriesConflict.qualifies(operation: .updateSeries, failure: .conflict(message: "x"), state: .conflict))
        XCTAssertFalse(ClubOpsEventSeriesConflict.qualifies(operation: .updateSeries, failure: .conflict(message: nil), state: .unknown))
        XCTAssertFalse(ClubOpsEventSeriesConflict.qualifies(operation: .updateSeries, failure: .unknown(message: nil), state: .conflict))
        XCTAssertFalse(ClubOpsEventSeriesConflict.qualifies(operation: .updateSeries, failure: nil, state: .conflict))
        XCTAssertFalse(ClubOpsEventSeriesConflict.qualifies(operation: .createSeries, failure: .conflict(message: nil), state: .conflict))
    }

}

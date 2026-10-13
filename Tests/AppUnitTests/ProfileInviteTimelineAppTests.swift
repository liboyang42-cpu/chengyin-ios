import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileInviteTimelineAppTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func reward(_ date: String) throws -> SocialInviteReward {
        let rows: [[String: Any]] = [["eventType": 5, "eventId": "201", "changePoints": 2, "createTime": date]]
        let scan = try JSONDecoder().decode(SocialRewardScan.self, from: JSONSerialization.data(withJSONObject: ["rows": rows, "total": 1]))
        return try XCTUnwrap(scan.rewards["201"])
    }
    func testRewardDateNeverBecomesMissingInvitationDateOrMonth() throws {
        let view = ProfileInviteTimelineDates(invitationTime: nil, reward: try reward("2026-10-01 10:00:00"))
        XCTAssertNil(view.invitation); XCTAssertNotNil(view.reward); XCTAssertTrue(view.hasReward)
        let row = try JSONDecoder().decode(SocialInvitedMember.self, from: Data(#"{"id":201}"#.utf8))
        XCTAssertEqual(ProfileInviteTimeline(members: [row]).months.map(\.id), [""])
    }
    func testInvalidInvitationAndRewardRemainSeparateUnknownFacts() throws {
        let view = ProfileInviteTimelineDates(invitationTime: "2026-02-30", reward: try reward("2026-13-01"))
        XCTAssertNil(view.invitation); XCTAssertNil(view.reward); XCTAssertTrue(view.hasReward)
        let absent = ProfileInviteTimelineDates(invitationTime: nil, reward: nil)
        XCTAssertNil(absent.invitation); XCTAssertNil(absent.reward); XCTAssertFalse(absent.hasReward)
    }
    func testDateOnlyFormattingDoesNotInventTimeOrMoveAcrossTimeZone() throws {
        let value = try XCTUnwrap(ProfileInviteTimeline.timestamp("2026-10-01"))
        let locale = Locale(identifier: "en_US_POSIX")
        let west = try XCTUnwrap(TimeZone(secondsFromGMT: -12 * 3600))
        XCTAssertEqual(ProfileInviteTimelineDates.display(value, locale: locale, timeZone: utc),
                       ProfileInviteTimelineDates.display(value, locale: locale, timeZone: west))
        XCTAssertFalse(ProfileInviteTimelineDates.display(value, locale: locale, timeZone: utc).contains(":"))
    }
    func testTimedFormattingUsesProvidedDeviceTimeZone() throws {
        let value = try XCTUnwrap(ProfileInviteTimeline.timestamp("2026-10-01T00:30:00+08:00"))
        let china = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600)), locale = Locale(identifier: "en_US_POSIX")
        XCTAssertNotEqual(ProfileInviteTimelineDates.display(value, locale: locale, timeZone: utc),
                          ProfileInviteTimelineDates.display(value, locale: locale, timeZone: china))
    }
    func testNormalLoadedModelProjectsBothPagesWithoutAdditionalReads() async throws {
        let reader = ProfileInviteRewardReviewFixtureReader(), model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        XCTAssertEqual(try XCTUnwrap(model.timeline(reader)).months[0].members.count, 2)
        XCTAssertEqual(reader.reads, 1)
        await model.start(reader, permit: model.permit(reader), reset: false)?.value
        XCTAssertEqual(try XCTUnwrap(model.timeline(reader)).months.map(\.id), ["2026-10", "2026-09"])
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(ProfileInviteRewardReview(scan: model.scan).cumulativePoints, 11)
    }
    func testSameOwnerHiddenDetailKeepsRowsButCannotStartOldRead() async throws {
        let reader = ProfileInviteRewardReviewFixtureReader(), model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        let oldPermit = model.permit(reader), timeline = model.timeline(reader)
        model.suspend()
        XCTAssertEqual(model.timeline(reader), timeline)
        XCTAssertNil(model.start(reader, permit: oldPermit, reset: false)); XCTAssertEqual(reader.reads, 1)
    }
    func testReplacementIdentityOrReaderCannotProjectOldTimelineBeforeReload() async {
        let reader = ProfileInviteRewardReviewFixtureReader(), model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        let replacement = ProfileInviteRewardReviewFixtureReader()
        model.bind(replacement)
        XCTAssertNil(model.timeline(reader)); XCTAssertNil(model.timeline(replacement))
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(replacement.reads, 0)
        reader.identity = .init(accountID: 82, epoch: 2)
        XCTAssertNil(model.timeline(reader))
    }
    func testPartialRewardLedgerDoesNotChangeInvitationGroupingOrClaimTotal() async throws {
        let reader = ProfileInviteRewardReviewFixtureReader("partial"), model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        XCTAssertNil(ProfileInviteRewardReview(scan: model.scan).cumulativePoints)
        XCTAssertEqual(try XCTUnwrap(model.timeline(reader)).months[0].members.count, 2)
        XCTAssertEqual(reader.reads, 1)
    }
    func testOrdinaryHistoryHostLoadsOnceWithExistingSyntheticReader() async throws {
        let reader = ProfileInviteRewardReviewFixtureReader()
        let host = UIHostingController(rootView: NavigationStack {
            SocialInviteHistoryView(reader: reader, squareReader: reader)
        }.environment(\.timeZone, utc))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<100 where reader.reads == 0 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(reader.reads, 1); XCTAssertNotNil(host.view)
    }
}

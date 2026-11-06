import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ClubMemberWelcomeCurrentTests: XCTestCase {
    private final class Seen: ClubWelcomeSeenStoring {
        var keys = Set<String>()
        var failRead = false
        func hasSeen(accountID: Int, clubID: Int, namespace: String) throws -> Bool {
            if failRead { throw APIError.malformedResponse }
            return keys.contains("\(namespace):\(accountID):\(clubID)")
        }
        func markSeen(accountID: Int, clubID: Int, namespace: String) throws {
            keys.insert("\(namespace):\(accountID):\(clubID)")
        }
    }
    private func club(_ fields: String = "") throws -> ClubRecord {
        try JSONDecoder().decode(ClubRecord.self, from: Data(("{\"id\":7,\"isJoined\":true" + fields + "}").utf8))
    }
    func testOriginalAccountClubSeenAndWithdrawal() throws {
        let seen = Seen(), flow = ClubWelcomePresentation(seen: Seen())
        let scoped = ClubWelcomePresentation(seen: seen)
        let record = try club()
        scoped.consider(club: record, identity: .init(accountID: 1, epoch: 2), namespace: "one", role: "player", active: true)
        XCTAssertNotNil(scoped.presentation)
        scoped.clear()
        scoped.consider(club: record, identity: .init(accountID: 1, epoch: 3), namespace: "one", role: "player", active: true)
        XCTAssertNil(scoped.presentation)
        scoped.consider(club: record, identity: .init(accountID: 2, epoch: 3), namespace: "one", role: "player", active: true)
        XCTAssertNotNil(scoped.presentation)
        scoped.consider(club: try club(",\"viewerIdentityUnavailable\":true"), identity: .init(accountID: 2, epoch: 3), namespace: "one", role: "player", active: true)
        XCTAssertNil(scoped.presentation)
        flow.consider(club: try club(",\"isOwner\":true"), identity: .init(accountID: 1, epoch: 2), namespace: "one", role: "player", active: true)
        XCTAssertNil(flow.presentation)
    }
    func testUnknownSettingAndFailedSeenReadNeverGrantOrPresent() throws {
        let seen = Seen(); seen.failRead = true
        let flow = ClubWelcomePresentation(seen: seen)
        let record = try club(",\"memberPostAllowed\":2,\"prioritySignupEnabled\":null")
        XCTAssertNil(record.memberPostAllowed); XCTAssertNil(record.prioritySignupEnabled)
        flow.consider(club: record, identity: .init(accountID: 1, epoch: 1), namespace: "test", role: "player", active: true)
        XCTAssertNil(flow.presentation)
    }
}

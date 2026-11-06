import XCTest
@testable import Questify

@MainActor final class GrowthAuditAvatarDefaultsTests: XCTestCase {
    func testDefaultAuditSnapshotDoesNotSupplyExternalAvatarURLs() {
        let snapshot = GrowthAndLeaderboardParitySnapshot()
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.avatarURL == nil && !$0.usesRemoteAvatar })
    }
    func testExplicitURLRequiresHTTPSHostAndNoEmbeddedCredentials() {
        func row(_ url: String, anonymous: Bool = false) -> GrowthLeaderboardAuditRow {
            .init(id: "synthetic", rank: 1, memberID: 7, nickname: "Synthetic", avatarURL: url,
                  scoreText: "7", badgeTitle: nil, isAnonymous: anonymous)
        }
        XCTAssertTrue(row("https://example.test/avatar.png").usesRemoteAvatar)
        XCTAssertTrue(row("HTTPS://example.test/avatar.png").usesRemoteAvatar)
        for url in ["https://", "https:avatar.png", "http://example.test/avatar.png", "https://user:password@example.test/avatar.png", ""] {
            XCTAssertFalse(row(url).usesRemoteAvatar, url)
        }
        XCTAssertFalse(row("https://example.test/avatar.png", anonymous: true).usesRemoteAvatar)
    }
}

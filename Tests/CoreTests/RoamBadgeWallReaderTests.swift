import XCTest
@testable import QuestifyCore

@MainActor final class RoamBadgeWallReaderTests: XCTestCase {
    private func roamIdentity(account: Int = 1, epoch: UInt64 = 2, namespace: String = "roam", market: String = "cn", host: String = "https://example.com") throws -> RoamExperienceIdentity {
        .init(scope: try RoamHistoryScope(market: market, deployment: URL(string: host)!, accountID: account, namespace: namespace), epoch: epoch)
    }
    private func setup() throws -> (Roam, Profile, RoamBadgeWallReader) {
        let roam = Roam(identity: try roamIdentity()), profile = Profile()
        return (roam, profile, .init(roam: roam, profile: profile))
    }
    private func badges() throws -> ProfileBadgeWall {
        let identity = try JSONDecoder().decode([ProfileIdentityBadge].self, from: Data(#"[{"badgeCode":"OWNED-ID","badgeName":"Identity","category":"EXPLORE","unlocked":false}]"#.utf8))
        let medals = try JSONDecoder().decode([ProfileMedal].self, from: Data(#"[{"templateId":31,"medalName":"Earned","getTime":"2026-10-11"}]"#.utf8))
        return .init(identities: identity, medals: medals)
    }
    func testConstructingBoundaryDoesNotReadAnyData() throws {
        let (roam, profile, reader) = try setup()
        XCTAssertTrue(reader.isCurrent); XCTAssertTrue(reader.isConfigured); XCTAssertEqual(reader.identity, profile.identity)
        XCTAssertEqual(profile.calls, []); XCTAssertEqual(roam.reads, 0)
    }
    func testSameAccountDelegatesOnlyActualBadgeReadUnchanged() async throws {
        let (roam, profile, reader) = try setup(); profile.result = try badges()
        let result = try await reader.profileBadges()
        XCTAssertEqual(result, profile.result); XCTAssertEqual(profile.calls, ["badges"]); XCTAssertEqual(roam.reads, 0)
    }
    func testPartialMedalFailureRemainsPartialNotEmpty() async throws {
        let (_, profile, reader) = try setup(); profile.result = .init(identities: try badges().identities, medals: nil, medalFailureMessage: "Synthetic partial result")
        let result = try await reader.profileBadges(); XCTAssertTrue(result.isPartial); XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.medalFailureMessage, "Synthetic partial result"); XCTAssertEqual(result.identities.count, 1)
    }
    func testSuccessfulEmptyWallRemainsEmptySuccess() async throws {
        let (_, _, reader) = try setup(); let result = try await reader.profileBadges()
        XCTAssertTrue(result.isEmpty); XCTAssertFalse(result.isPartial)
    }
    func testCurrentReadFailurePassesThroughForExistingRetryUI() async throws {
        let (_, profile, reader) = try setup(); profile.failure = APIError.httpStatus(503)
        do { _ = try await reader.profileBadges(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
    }
    func testRetryUsesSameBoundaryAndCurrentSourceData() async throws {
        let (_, profile, reader) = try setup(); profile.failure = APIError.httpStatus(503)
        _ = try? await reader.profileBadges(); profile.failure = nil; profile.result = try badges()
        let result = try await reader.profileBadges(); XCTAssertEqual(result, profile.result); XCTAssertEqual(profile.calls, ["badges","badges"])
    }
    func testNoRoamOrProfileIdentityCannotRead() async throws {
        let (roam, profile, _) = try setup(); roam.identity = nil
        let missingRoam = RoamBadgeWallReader(roam: roam, profile: profile)
        XCTAssertNil(missingRoam.identity); XCTAssertFalse(missingRoam.isConfigured)
        do { _ = try await missingRoam.profileBadges(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        roam.identity = try roamIdentity(); profile.identity = nil
        let missingProfile = RoamBadgeWallReader(roam: roam, profile: profile)
        _ = try? await missingProfile.profileBadges(); XCTAssertTrue(profile.calls.isEmpty)
    }
    func testMismatchedAccountCannotReadOtherPersonsWall() async throws {
        let (roam, profile, _) = try setup(); profile.identity = .init(accountID: 9, epoch: 2)
        let reader = RoamBadgeWallReader(roam: roam, profile: profile)
        XCTAssertFalse(reader.isCurrent); _ = try? await reader.profileBadges(); XCTAssertTrue(profile.calls.isEmpty)
    }
    func testMismatchedLoginEpochCannotCrossSessions() async throws {
        let (roam, profile, _) = try setup(); profile.identity = .init(accountID: 1, epoch: 3)
        let reader = RoamBadgeWallReader(roam: roam, profile: profile)
        XCTAssertFalse(reader.isCurrent); _ = try? await reader.profileBadges(); XCTAssertTrue(profile.calls.isEmpty)
    }
    func testRoamRemoteReadConfigurationIsNotNewBadgePermission() async throws {
        let (roam, profile, reader) = try setup(); roam.isConfigured = false
        _ = try await reader.profileBadges(); XCTAssertEqual(profile.calls, ["badges"])
    }
    func testUnavailableProfileContractDoesNotDelegate() async throws {
        let (roam, profile, _) = try setup(); profile.isConfigured = false
        let reader = RoamBadgeWallReader(roam: roam, profile: profile)
        XCTAssertTrue(reader.isCurrent); XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.profileBadges(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(profile.calls.isEmpty)
    }
    func testAllRoamScopeDimensionsRetireBoundary() async throws {
        let values = try [roamIdentity(account: 2), roamIdentity(epoch: 3), roamIdentity(namespace: "other"), roamIdentity(market: "us"), roamIdentity(host: "https://example.org")]
        for value in values {
            let (roam, profile, reader) = try setup(); roam.identity = value
            XCTAssertFalse(reader.isCurrent); XCTAssertNil(reader.identity)
            _ = try? await reader.profileBadges(); XCTAssertTrue(profile.calls.isEmpty)
        }
    }
    func testUnicodeNamespaceBytesAreNotNormalizedTogether() throws {
        let (roam, profile, _) = try setup(); roam.identity = try roamIdentity(namespace: "\u{00E9}")
        let reader = RoamBadgeWallReader(roam: roam, profile: profile); roam.identity = try roamIdentity(namespace: "e\u{0301}")
        XCTAssertFalse(reader.isCurrent)
    }
    func testProfileViewerAndApprovalRevisionRetireBoundary() throws {
        let (_, profile, reader) = try setup(); profile.identity = .init(accountID: 1, epoch: 2, viewerRevision: 1)
        XCTAssertFalse(reader.isCurrent)
        let (roam2, profile2, _) = try setup(); profile2.identity = .init(accountID: 1, epoch: 2, approvalRevision: UUID())
        let other = RoamBadgeWallReader(roam: roam2, profile: profile2); profile2.identity = .init(accountID: 1, epoch: 2, approvalRevision: UUID())
        XCTAssertFalse(other.isCurrent)
    }
    func testConfigurationChangeRequiresFreshNavigationBoundary() throws {
        let (_, profile, reader) = try setup(); profile.isConfigured = false
        XCTAssertFalse(reader.isCurrent); XCTAssertNil(reader.identity)
    }
    func testReaderObjectsArePartOfPresentationOwner() throws {
        let (roam, profile, reader) = try setup(); let replacement = Profile()
        XCTAssertNotEqual(reader.origin, RoamBadgeWallReadOwner(roam: roam, profile: replacement))
        let otherRoam = Roam(identity: try roamIdentity())
        XCTAssertNotEqual(reader.origin, RoamBadgeWallReadOwner(roam: otherRoam, profile: profile))
    }
    func testLateSuccessAfterAccountChangeIsDiscarded() async throws {
        let (roam, profile, reader) = try setup(); profile.afterRead = { roam.identity = nil }
        do { _ = try await reader.profileBadges(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(reader.identity)
    }
    func testLateErrorAfterProfileScopeChangeDoesNotLeakToNewOwner() async throws {
        let (_, profile, reader) = try setup(); profile.afterRead = { profile.identity = .init(accountID: 2, epoch: 3) }; profile.failure = APIError.unauthorized
        do { _ = try await reader.profileBadges(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testCanceledReadIgnoresUnderlyingLateCompletion() async throws {
        let (_, profile, reader) = try setup(); profile.suspend = true
        let task = Task { try await reader.profileBadges() }
        while profile.pending == nil { await Task.yield() }
        task.cancel(); profile.pending?.resume(returning: .init(identities: [], medals: [])); profile.pending = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testUnrelatedProfileMethodsAreNeverDelegated() async throws {
        let (_, profile, reader) = try setup()
        do { _ = try await reader.profileOrders(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await reader.profileOrder(id: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await reader.profileParticipants(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await reader.profileParticipant(id: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(profile.calls.isEmpty)
    }
    @MainActor private final class Roam: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = true
        var isOfflineExample = true
        var reads = 0
        init(identity: RoamExperienceIdentity?) { self.identity = identity }
        func history() throws -> [RoamHistoryRecord] { reads += 1; return [] }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { reads += 1; throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { reads += 1; throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { reads += 1; throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { reads += 1; throw APIError.notConfigured }
    }
    @MainActor private final class Profile: ProfileReading {
        var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 2)
        var isConfigured = true
        var calls: [String] = []
        var result = ProfileBadgeWall(identities: [], medals: [])
        var failure: Error?
        var afterRead: (() -> Void)?
        var suspend = false
        var pending: CheckedContinuation<ProfileBadgeWall, Error>?
        func profileBadges() async throws -> ProfileBadgeWall {
            calls.append("badges"); afterRead?(); if let failure { throw failure }
            if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }; return result
        }
        func profileOrders() async throws -> [ProfileOrder] { calls.append("orders"); throw APIError.invalidRequest }
        func profileOrder(id: Int) async throws -> ProfileOrder { calls.append("order"); throw APIError.invalidRequest }
        func profileParticipants() async throws -> [ProfileParticipant] { calls.append("participants"); throw APIError.invalidRequest }
        func profileParticipant(id: Int) async throws -> ProfileParticipant { calls.append("participant"); throw APIError.invalidRequest }
    }
}

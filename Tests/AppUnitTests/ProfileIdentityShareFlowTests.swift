import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileIdentityShareFlowTests: XCTestCase {
    private final class Reader: SocialAccountReading {
        var identity = SocialAccountIdentity(accountID: 7, epoch: 1, role: "player")
        var presentationRevision: UInt64 = 0
        var isConfigured = true
        var isOfflineExample = false
        var reads = 0
        func publicProfile(memberID: Int) async throws -> SocialPublicProfile { reads += 1; throw APIError.invalidRequest }
        func informationList() async throws -> [SocialInformation] { reads += 1; throw APIError.invalidRequest }
        func information(id: Int) async throws -> SocialInformation { reads += 1; throw APIError.invalidRequest }
        func invitationHistory(page: Int) async throws -> SocialInviteHistory { reads += 1; throw APIError.invalidRequest }
    }
    private final class Scope { var current = true }
    private func profile(name: String = "Synthetic explorer") throws -> SocialPublicProfile {
        try JSONDecoder().decode(SocialPublicProfile.self, from: JSONSerialization.data(withJSONObject: ["id": 7, "nickname": name, "introduction": "City walks"]))
    }
    private func model(_ reader: Reader, _ scope: Scope = Scope()) throws -> ProfileIdentityShareModel {
        ProfileIdentityShareModel(profile: try profile(), reader: reader, isCurrent: { scope.current })
    }
    func testNormalSelfPreviewHandoffAndCloseNeedNoRead() throws {
        let r = Reader(), m = try model(r)
        m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        XCTAssertNil(m.handoff); m.beginHandoff(p); let h = try XCTUnwrap(m.handoff)
        XCTAssertEqual(h.text, p.text); XCTAssertEqual(h.previewID, p.id)
        m.finishHandoff(h); XCTAssertNil(m.handoff); XCTAssertEqual(m.preview?.id, p.id)
        m.close(p); XCTAssertNil(m.preview); XCTAssertEqual(r.reads, 0)
    }
    func testCancelPreviewDoesNotCreateSystemHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card")
        let p = try XCTUnwrap(m.preview); m.close(p); m.beginHandoff(p)
        XCTAssertNil(m.preview); XCTAssertNil(m.handoff); XCTAssertEqual(r.reads, 0)
    }
    func testRepeatedTapDoesNotReplacePreviewOrHandoff() throws {
        let m = try model(Reader()); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        m.open(title: "Other"); XCTAssertEqual(m.preview?.id, p.id)
        m.beginHandoff(p); let h = try XCTUnwrap(m.handoff); m.beginHandoff(p)
        XCTAssertEqual(m.handoff?.id, h.id)
    }
    func testAccountChangeBeforeConfirmationPreventsHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.identity = .init(accountID: 8, epoch: 2, role: "player"); m.beginHandoff(p)
        XCTAssertFalse(m.canShare); XCTAssertNil(m.handoff)
    }
    func testSameAccountNewEpochPreventsHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.identity = .init(accountID: 7, epoch: 2, role: "player"); m.beginHandoff(p)
        XCTAssertNil(m.handoff)
    }
    func testPresentationRevisionBlocksUnobservedABATransition() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.presentationRevision += 2; m.beginHandoff(p); m.activate()
        XCTAssertFalse(m.canShare); XCTAssertNil(m.handoff)
    }
    func testRawRoleBytesFenceCanonicallyEquivalentReplacement() throws {
        let r = Reader(); r.identity = .init(accountID: 7, epoch: 1, role: "caf\u{00e9}")
        let m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.identity = .init(accountID: 7, epoch: 1, role: "cafe\u{0301}"); m.beginHandoff(p)
        XCTAssertNil(m.handoff)
    }
    func testParentScopeRetirementPreventsHandoff() throws {
        let r = Reader(), scope = Scope(), m = try model(r, scope); m.open(title: "Card")
        let p = try XCTUnwrap(m.preview); scope.current = false; m.beginHandoff(p)
        XCTAssertNil(m.handoff); XCTAssertFalse(m.canShare)
    }
    func testRetiredCallbackCannotCloseLaterPreview() throws {
        let m = try model(Reader()); m.open(title: "Card"); let first = try XCTUnwrap(m.preview)
        m.beginHandoff(first); let old = try XCTUnwrap(m.handoff); m.retire(); m.activate()
        m.open(title: "Card"); let second = try XCTUnwrap(m.preview); m.beginHandoff(second)
        let current = try XCTUnwrap(m.handoff); m.finishHandoff(old); m.close(first)
        XCTAssertEqual(m.preview?.id, second.id); XCTAssertEqual(m.handoff?.id, current.id)
    }
    func testCloseAndReturnCanOpenFreshPreviewInSameScope() throws {
        let m = try model(Reader()); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        m.retire(); XCTAssertNil(m.preview); m.activate(); m.open(title: "Card")
        XCTAssertNotEqual(m.preview?.id, p.id)
    }
    func testGuestOtherMemberAndUnconfiguredNeverOpen() throws {
        for member in [nil, 8] as [Int?] {
            let r = Reader(); r.identity = .init(accountID: member, epoch: 1)
            let m = try model(r); m.open(title: "Card"); XCTAssertNil(m.preview)
        }
        let r = Reader(); r.isConfigured = false; let m = try model(r); m.open(title: "Card"); XCTAssertNil(m.preview)
    }
    func testReplacementReaderAndChangedProfileHaveDistinctViewIdentity() throws {
        let a = Reader(), b = Reader(), p = try profile()
        XCTAssertNotEqual(ProfileIdentityShareViewIdentity(profile: p, reader: a), ProfileIdentityShareViewIdentity(profile: p, reader: b))
        XCTAssertNotEqual(ProfileIdentityShareViewIdentity(profile: p, reader: a), ProfileIdentityShareViewIdentity(profile: try profile(name: "New name"), reader: a))
    }
    func testNormalSectionConstructionDoesNotReadOrShare() throws {
        let r = Reader(); let _ = ProfileIdentityShareSection(profile: try profile(), reader: r, isCurrent: { true })
        XCTAssertEqual(r.reads, 0)
    }
}

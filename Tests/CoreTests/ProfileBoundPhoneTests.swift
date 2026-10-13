import XCTest
@testable import QuestifyCore

private func phoneSnapshot(_ phone: Any? = "13800138000", id: Int = 1, includesPhone: Bool = true) throws -> ProfileEditSnapshot {
    var row: [String: Any] = ["id": id, "nickname": "Synthetic owner", "introduction": "", "avatar": "", "wechat": "", "casePics": "", "tagIds": ""]
    if includesPhone { row["phone"] = phone ?? NSNull() }
    return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: row))
}
private actor PhoneSnapshotSource: ProfileEditServing {
    var value: ProfileEditSnapshot
    private var paused = false
    private var pending: CheckedContinuation<ProfileEditSnapshot, Error>?
    private(set) var writes = 0
    init(_ value: ProfileEditSnapshot) { self.value = value }
    func read(token: String) async throws -> ProfileEditSnapshot {
        if paused { paused = false; return try await withCheckedThrowingContinuation { pending = $0 } }
        return value
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws { writes += 1 }
    func replace(_ snapshot: ProfileEditSnapshot) { value = snapshot }
    func pauseNext() { paused = true }
    func waitForPending() async { while pending == nil { await Task.yield() } }
    func finish() { pending?.resume(returning: value); pending = nil }
}
final class ProfileBoundPhoneTests: XCTestCase {
    func testSupportedPhoneIsMaskedDuringDecodeWithoutRetainingRawValue() throws {
        let value = try phoneSnapshot()
        XCTAssertEqual(value.phoneDisplay, .masked("138****8000"))
        XCTAssertFalse(String(reflecting: value).contains("13800138000"))
    }
    func testFormattedAndInternationalPhoneRetainOnlySourcePrefixAndSuffix() throws {
        XCTAssertEqual(try phoneSnapshot(" +86 (138) 0013-8000 ").phoneDisplay, .masked("861****8000"))
        XCTAssertEqual(try phoneSnapshot("138.0013.8000").phoneDisplay, .masked("138****8000"))
    }
    func testMissingWrongTypeAndMalformedNonemptyAreUnknownNotUnbound() throws {
        XCTAssertEqual(try phoneSnapshot(includesPhone: false).phoneDisplay, .unavailable)
        let malformed: [Any] = [true, 13800138000, ["value": "13800138000"], ["13800138000"], "1234567", "138****8000", "https://example.test/13800138000", "１３８００１３８０００", String(repeating: "1", count: 65)]
        for value in malformed {
            XCTAssertEqual(try phoneSnapshot(value).phoneDisplay, .unavailable)
        }
    }
    func testExplicitNullAndEmptyAreUnboundAndLegacyFieldsStillDecode() throws {
        let values: [Any?] = [nil, "", "  \n"]
        for value in values {
            let snapshot = try phoneSnapshot(value)
            XCTAssertEqual(snapshot.phoneDisplay, .unbound)
            XCTAssertEqual(snapshot.nickname, "Synthetic owner"); XCTAssertEqual(snapshot.casePics, "")
        }
    }
    func testPhoneIsNeverAnEditableDraftOrEncodedReplacementField() throws {
        let value = try phoneSnapshot()
        XCTAssertFalse(value.draft.hasChanges(comparedTo: value))
        let payload = try ProfileEditPayload(draft: value.draft, preserving: value)
        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["name", "introduction", "avatar", "wechat", "casePics", "tagIds"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("138"))
    }
    func testReadOnlyMetadataDoesNotAlterAvatarHashOrPayloadReadbackFields() throws {
        let first = try phoneSnapshot("13800138000"), second = try phoneSnapshot("13900139000")
        XCTAssertEqual(ProfileAvatarExact.snapshot(first), ProfileAvatarExact.snapshot(second))
        let payload = try ProfileEditPayload(draft: first.draft, preserving: first)
        XCTAssertTrue(payload.matches(second)); XCTAssertFalse(second.draft.hasChanges(comparedTo: first))
        // Synthesized snapshot comparison can conservatively ask for another review.
        XCTAssertNotEqual(first, second)
    }
    @MainActor func testCurrentPhoneHidesImmediatelyForAccountEpochTokenRevisionOrLogout() async throws {
        let initial = try ProfileEditSession(accountID: 1, epoch: 1, token: "synthetic-phone", viewerRevision: 1)
        let replacements: [ProfileEditSession?] = [nil,
            try .init(accountID: 2, epoch: 1, token: "synthetic-phone", viewerRevision: 1),
            try .init(accountID: 1, epoch: 2, token: "synthetic-phone", viewerRevision: 1),
            try .init(accountID: 1, epoch: 1, token: "synthetic-other", viewerRevision: 1),
            try .init(accountID: 1, epoch: 1, token: "synthetic-phone", viewerRevision: 2)]
        for replacement in replacements {
            var current: ProfileEditSession? = initial
            let source = PhoneSnapshotSource(try phoneSnapshot())
            let coordinator = ProfileEditCoordinator(service: source, currentSession: { current })
            _ = await coordinator.load(); XCTAssertEqual(coordinator.phoneDisplay, .masked("138****8000"))
            current = replacement
            XCTAssertNotNil(coordinator.snapshot) // The asynchronous page task has not run.
            XCTAssertNil(coordinator.phoneDisplay)
            let writes = await source.writes; XCTAssertEqual(writes, 0)
        }
    }
    @MainActor func testForeignMemberResponseNeverExposesPhone() async throws {
        let session = try ProfileEditSession(accountID: 1, epoch: 1, token: "synthetic-phone")
        let source = PhoneSnapshotSource(try phoneSnapshot(id: 2))
        let coordinator = ProfileEditCoordinator(service: source, currentSession: { session })
        _ = await coordinator.load(); XCTAssertNil(coordinator.phoneDisplay); XCTAssertNil(coordinator.snapshot)
    }
    @MainActor func testLateOldSessionReadCannotPublishMaskedPhone() async throws {
        var current: ProfileEditSession? = try .init(accountID: 1, epoch: 1, token: "synthetic-phone")
        let source = PhoneSnapshotSource(try phoneSnapshot()), coordinator = ProfileEditCoordinator(service: nil, currentSession: { current })
        XCTAssertNil(coordinator.phoneDisplay)
        let active = ProfileEditCoordinator(service: source, currentSession: { current })
        await source.pauseNext()
        let pending = Task { await active.load() }
        await source.waitForPending(); current = try .init(accountID: 2, epoch: 2, token: "synthetic-new")
        await source.finish(); _ = await pending.value
        XCTAssertNil(active.phoneDisplay); XCTAssertNil(active.snapshot)
    }
    @MainActor func testChangedReadOnlyMetadataRequiresFreshReviewWithoutDispatchingSave() async throws {
        let session = try ProfileEditSession(accountID: 1, epoch: 1, token: "synthetic-phone")
        let source = PhoneSnapshotSource(try phoneSnapshot())
        let coordinator = ProfileEditCoordinator(service: source, currentSession: { session })
        _ = await coordinator.load()
        var draft = try XCTUnwrap(coordinator.snapshot).draft; draft.name = "Changed synthetic name"
        await coordinator.prepare(draft)
        let review = try XCTUnwrap(coordinator.confirmation)
        await source.replace(try phoneSnapshot("13900139000"))
        await coordinator.save(review)
        let writes = await source.writes; XCTAssertEqual(writes, 0)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.changed")
        XCTAssertEqual(coordinator.phoneDisplay, .masked("139****9000"))
    }

}

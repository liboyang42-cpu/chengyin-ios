import XCTest
@testable import QuestifyCore

@MainActor final class ProfileLocalCoverTests: XCTestCase {
    private final class Reader: SocialAccountReading {
        var identity = SocialAccountIdentity(accountID: 7, epoch: 1, role: "player")
        var presentationRevision: UInt64 = 0
        let isConfigured = false, isOfflineExample = true
        func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
        func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    }
    private final class Store: ProfileLocalCoverStoring {
        var images: [ProfileLocalCoverOwner: RetainedSelectedImage] = [:]
        var writes = 0, reads = 0
        var fails = false, failsRead = false, corruptReadback = false
        func read(owner: ProfileLocalCoverOwner) throws -> RetainedSelectedImage? {
            reads += 1
            if failsRead { throw ProfileLocalCoverFailure.storage }
            return corruptReadback && writes > 0 ? nil : images[owner]
        }
        func replace(_ image: RetainedSelectedImage?, owner: ProfileLocalCoverOwner) throws {
            if fails { throw ProfileLocalCoverFailure.storage }; writes += 1; images[owner] = image
        }
    }
    private func image(_ seed: UInt8 = 1, width: Int = 320, height: Int = 180) throws -> RetainedSelectedImage {
        try .init(jpeg: Data([255,216,255,seed]), width: width, height: height)
    }
    private func owner(_ id: Int = 7, namespace: String = "synthetic.realm.A") throws -> ProfileLocalCoverOwner { try .init(accountID: id, namespace: namespace) }
    private func controller(_ r: Reader, _ s: any ProfileLocalCoverStoring, owner: ProfileLocalCoverOwner? = nil) throws -> ProfileLocalCoverController {
        let o = try owner ?? self.owner(), context = ProfileLocalCoverContext(owner: o, reader: r)
        return .init(context: context, store: s, current: { .init(owner: o, reader: r) })
    }
    func testCancelPreviewNeverPersists() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image())
        c.cancel(try XCTUnwrap(c.review)); XCTAssertEqual(s.writes,0); XCTAssertNil(c.saved); XCTAssertNil(c.review)
    }
    func testConfirmPersistsAndRereadsExactlyOnce() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); let value=try image(); c.prepare(value)
        let review=try XCTUnwrap(c.review); c.confirm(review); c.confirm(review)
        XCTAssertEqual(s.writes,1); XCTAssertEqual(s.reads,3); XCTAssertTrue(ProfileLocalCoverController.sameImage(c.saved,value)); XCTAssertEqual(c.messageKey,"profile.localCover.saved")
    }
    func testNewControllerRestoresSameOwnersCover() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image()); c.confirm(try XCTUnwrap(c.review))
        let reopened=try controller(r,s); reopened.load(); XCTAssertNotNil(reopened.saved)
    }
    func testRestoreDefaultNeedsReviewAndCancelDoesNotDelete() throws {
        let r=Reader(), s=Store(), o=try owner(); s.images[o]=try image(); let c=try controller(r,s); c.load()
        c.prepareDefault(); let review=try XCTUnwrap(c.review); XCTAssertNil(review.image); c.cancel(review)
        XCTAssertEqual(s.writes,0); XCTAssertNotNil(s.images[o])
        c.prepareDefault(); c.confirm(try XCTUnwrap(c.review)); XCTAssertNil(c.saved); XCTAssertNil(s.images[o]); XCTAssertEqual(s.writes,1)
    }
    func testAccountAndDeploymentHaveDifferentStorageKeys() throws {
        let a=try owner(), b=try owner(8), other=try owner(namespace:"synthetic.realm.B")
        XCTAssertNotEqual(a.storageKey,b.storageKey); XCTAssertNotEqual(a.storageKey,other.storageKey)
        XCTAssertEqual(a.storageKey.count,64); XCTAssertTrue(a.storageKey.allSatisfy(\.isHexDigit))
    }
    func testSwitchAccountHidesAndRejectsOldConfirmation() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image()); let review=try XCTUnwrap(c.review)
        r.identity = .init(accountID:8,epoch:2); XCTAssertFalse(c.ownsContext); c.confirm(review); XCTAssertEqual(s.writes,0)
        c.load(); XCTAssertNil(c.saved); XCTAssertNil(c.review)
    }
    func testRevisionABARetiresOldReview() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image()); let review=try XCTUnwrap(c.review)
        r.presentationRevision += 2; c.confirm(review); XCTAssertEqual(s.writes,0); XCTAssertFalse(c.canEdit)
    }
    func testOtherMembersCoverCannotLoadOrSave() throws {
        let r=Reader(), s=Store(), c=try controller(r,s,owner:owner(8)); c.load(); c.prepare(try image())
        XCTAssertEqual(s.reads,0); XCTAssertEqual(s.writes,0); XCTAssertNil(c.review)
    }
    func testSaveFailureRetainsPriorImageAndRequiresReload() throws {
        let r=Reader(), s=Store(), o=try owner(); s.images[o]=try image(1); let c=try controller(r,s); c.load()
        c.prepare(try image(2)); s.fails=true; c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(c.saved?.jpeg,try image(1).jpeg); XCTAssertEqual(c.messageKey,"profile.localCover.failed"); XCTAssertFalse(c.loaded); XCTAssertEqual(s.writes,0)
    }
    func testReadbackFailureCannotClaimSuccess() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image()); s.corruptReadback=true
        c.confirm(try XCTUnwrap(c.review)); XCTAssertNil(c.saved); XCTAssertEqual(c.messageKey,"profile.localCover.failed"); XCTAssertFalse(c.canEdit)
        s.corruptReadback=false; c.load(); XCTAssertNotNil(c.saved); XCTAssertTrue(c.canEdit)
    }
    func testConcurrentCoverChangeRequiresFreshLoad() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image(1)); s.images[try owner()]=try image(2)
        c.confirm(try XCTUnwrap(c.review)); XCTAssertEqual(s.writes,0); XCTAssertEqual(c.messageKey,"profile.localCover.changed"); XCTAssertFalse(c.canEdit)
    }
    func testOldReviewAfterNewPreviewCannotCommit() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image(1)); let old=try XCTUnwrap(c.review)
        c.prepare(try image(2)); c.confirm(old); XCTAssertEqual(s.writes,0); XCTAssertEqual(c.review?.image?.jpeg,try image(2).jpeg)
    }
    func testWrongRatioRejectedBeforeStorage() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image(width:200,height:200))
        XCTAssertNil(c.review); XCTAssertEqual(s.writes,0); XCTAssertEqual(c.messageKey,"profile.localCover.invalid")
    }
    func testNoImageDefaultActionIsANoop() throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepareDefault(); XCTAssertNil(c.review); XCTAssertEqual(s.writes,0)
    }
    func testDurableFileRoundTripAndOwnerIsolation() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let s=ProfileLocalCoverFileStore(directory:directory), a=try owner(), b=try owner(8), value=try image()
        try s.replace(value,owner:a); XCTAssertTrue(ProfileLocalCoverController.sameImage(try s.read(owner:a),value)); XCTAssertNil(try s.read(owner:b))
        let reopened=ProfileLocalCoverFileStore(directory:directory); XCTAssertNotNil(try reopened.read(owner:a))
        try reopened.replace(nil,owner:b); XCTAssertNotNil(try reopened.read(owner:a))
        try reopened.replace(nil,owner:a); XCTAssertNil(try reopened.read(owner:a))
    }
    func testMislabeledFileOwnerAndCorruptDataAreRejected() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let s=ProfileLocalCoverFileStore(directory:directory), a=try owner(), b=try owner(8)
        try s.replace(try image(),owner:a)
        let source=directory.appendingPathComponent(a.storageKey+".cover"), destination=directory.appendingPathComponent(b.storageKey+".cover")
        try FileManager.default.copyItem(at:source,to:destination); XCTAssertThrowsError(try s.read(owner:b))
        try Data("invalid".utf8).write(to:source); XCTAssertThrowsError(try s.read(owner:a))
    }
    func testOwnerRejectsUnscopedOrInvalidAccount() {
        XCTAssertThrowsError(try owner(0)); XCTAssertThrowsError(try owner(namespace:""))
    }
    func testCancelledConfirmationNeverWrites() async throws {
        let r=Reader(), s=Store(), c=try controller(r,s); c.load(); c.prepare(try image()); let review=try XCTUnwrap(c.review)
        let task=Task { withUnsafeCurrentTask { $0?.cancel() }; c.confirm(review) }; await task.value
        XCTAssertEqual(s.writes,0)
    }
}

import XCTest
@testable import QuestifyCore

@MainActor final class ProfileOrderNumberCopyTests: XCTestCase {
    private final class Reader: ProfileReading {
        var identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1, viewerRevision: 2, approvalRevision: UUID())
        var isConfigured = true
        var reads = 0
        func profileOrders() async throws -> [ProfileOrder] { reads += 1; throw APIError.notConfigured }
        func profileOrder(id: Int) async throws -> ProfileOrder { reads += 1; throw APIError.notConfigured }
        func profileParticipants() async throws -> [ProfileParticipant] { reads += 1; throw APIError.notConfigured }
        func profileParticipant(id: Int) async throws -> ProfileParticipant { reads += 1; throw APIError.notConfigured }
        func profileBadges() async throws -> ProfileBadgeWall { reads += 1; throw APIError.notConfigured }
    }
    private let reader = Reader()
    private func order(number: Any = " 000012-é ", id: Int = 41, member: Any = 81, payment: Int = 0) throws -> ProfileOrder {
        let value: [String: Any] = ["id":id,"memberId":member,"registrationNo":number,"paymentStatus":payment]
        return try JSONDecoder().decode(ProfileOrder.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func context(_ order: ProfileOrder? = nil) throws -> ProfileOrderNumberCopyContext {
        try XCTUnwrap(ProfileOrderNumberCopyContext.capture(order: order ?? self.order(), requestedID: 41, reader: reader))
    }
    private func model() throws -> ProfileOrderNumberCopyModel {
        let c = try context(), m = ProfileOrderNumberCopyModel(context: c); m.appear(current: c); return m
    }
    func testNoRequestOrCopyOccursAtCaptureAndConstruction() throws {
        let m = ProfileOrderNumberCopyModel(context: try context()); XCTAssertNil(m.permit); XCTAssertNil(m.result); XCTAssertEqual(reader.reads, 0)
    }
    func testMissingBlankAndWhitespaceNumbersHaveNoAction() throws {
        let values: [Any] = [NSNull(),""," \n\t"]
        for raw in values {
            XCTAssertNil(ProfileOrderNumberCopyContext.capture(order: try order(number: raw), requestedID: 41, reader: reader))
        }
    }
    func testStrictWireDecoderDoesNotTurnNumericOrBooleanIntoMadeUpString() {
        let values: [Any] = [123,false]
        for raw in values { XCTAssertThrowsError(try order(number: raw)) }
    }
    func testExactDetailAndCurrentMemberRequired() throws {
        for value in [try order(id: 42), try order(member: 82), try order(member: NSNull())] {
            XCTAssertNil(ProfileOrderNumberCopyContext.capture(order: value, requestedID: 41, reader: reader))
        }
        XCTAssertNil(ProfileOrderNumberCopyContext.capture(order: try order(), requestedID: 0, reader: reader))
    }
    func testNoPaymentStatusGateIsInventedForSourceCopyAction() throws {
        for payment in [0,1,2,3,99] { XCTAssertNotNil(try context(order(payment: payment))) }
    }
    func testDisabledReaderAndLogoutCannotCapture() throws {
        reader.isConfigured = false; XCTAssertNil(ProfileOrderNumberCopyContext.capture(order: try order(), requestedID: 41, reader: reader))
        reader.isConfigured = true; reader.identity = nil
        XCTAssertNil(ProfileOrderNumberCopyContext.capture(order: try order(), requestedID: 41, reader: reader))
    }
    func testCopyRetainsLeadingZerosWhitespaceAndUnicodeBytes() throws {
        let m = try model(), c = try context(); var copied: [String] = []
        let result = m.copy(try XCTUnwrap(m.permit), current: { c }, write: { copied.append($0) })
        XCTAssertEqual(result, .copied); XCTAssertEqual(copied.map { Data($0.utf8) }, [Data(c.registrationNo.utf8)])
        XCTAssertEqual(m.result, .copied); XCTAssertEqual(reader.reads, 0)
    }
    func testSameRenderedPermitCannotCopyTwiceButFreshClickCan() throws {
        let m = try model(), c = try context(), old = try XCTUnwrap(m.permit); var copied = 0
        XCTAssertEqual(m.copy(old, current: { c }, write: { _ in copied += 1 }), .copied)
        XCTAssertNil(m.copy(old, current: { c }, write: { _ in copied += 1 }))
        XCTAssertEqual(m.copy(try XCTUnwrap(m.permit), current: { c }, write: { _ in copied += 1 }), .copied)
        XCTAssertEqual(copied, 2)
    }
    func testReentrantCopyCannotWriteAgain() throws {
        let m = try model(), c = try context(); var copied = 0
        _ = m.copy(try XCTUnwrap(m.permit), current: { c }) { _ in
            copied += 1
            XCTAssertNil(m.copy(try XCTUnwrap(m.permit), current: { c }, write: { _ in copied += 1 }))
        }
        XCTAssertEqual(copied, 1)
    }
    func testFailedCopyCanRetryWithNewPermitAndDoesNotReadClipboard() throws {
        let m = try model(), c = try context(), old = try XCTUnwrap(m.permit)
        XCTAssertEqual(m.copy(old, current: { c }, write: { _ in throw APIError.notConfigured }), .failed)
        XCTAssertEqual(m.result, .failed)
        XCTAssertEqual(m.copy(try XCTUnwrap(m.permit), current: { c }, write: { _ in }), .copied)
    }
    func testSuspendedPageAndOldPermitAfterReturnCannotCopy() throws {
        let m = try model(), c = try context(), old = try XCTUnwrap(m.permit); var copies = 0
        m.suspend(); XCTAssertNil(m.copy(old, current: { c }, write: { _ in copies += 1 }))
        m.appear(current: c); XCTAssertNil(m.copy(old, current: { c }, write: { _ in copies += 1 }))
        XCTAssertNotNil(m.permit); XCTAssertEqual(copies, 0); XCTAssertNil(m.result)
    }
    func testRetiredContextCannotRebindAfterSameAccountReturns() throws {
        let m = try model(), c = try context(); m.retire(); m.appear(current: c)
        XCTAssertFalse(m.matches(c)); XCTAssertNil(m.permit)
    }
    func testWholeIdentityEpochViewerAndApprovalRejectOldClicks() throws {
        let original = try XCTUnwrap(reader.identity)
        for replacement in [ProfileReadIdentity(accountID:81,epoch:2,viewerRevision:2,approvalRevision:original.approvalRevision),
                            .init(accountID:81,epoch:1,viewerRevision:3,approvalRevision:original.approvalRevision),
                            .init(accountID:81,epoch:1,viewerRevision:2,approvalRevision:UUID())] {
            reader.identity = original; let m = try model(), permit = try XCTUnwrap(m.permit)
            reader.identity = replacement; let newer = try context(); var copies = 0
            XCTAssertNil(m.copy(permit, current: { newer }, write: { _ in copies += 1 })); XCTAssertEqual(copies, 0)
        }
    }
    func testDifferentReaderObjectWithSameIdentityIsNotAccepted() throws {
        let m = try model(), other = Reader(); other.identity = reader.identity
        let replacement = try XCTUnwrap(ProfileOrderNumberCopyContext.capture(order: order(), requestedID: 41, reader: other))
        XCTAssertNil(m.copy(try XCTUnwrap(m.permit), current: { replacement }, write: { _ in XCTFail() }))
    }
    func testSameNumberCanonicalUnicodeChangeIsNotAccepted() throws {
        let first = try context(order(number:"é")), newer = try context(order(number:"e\u{301}"))
        XCTAssertNotEqual(first, newer); let m = ProfileOrderNumberCopyModel(context: first); m.appear(current: first)
        XCTAssertNil(m.copy(try XCTUnwrap(m.permit), current: { newer }, write: { _ in XCTFail() }))
    }
    func testChangedNumberNeverCopiesOldRenderedNumber() throws {
        let m = try model(), newer = try context(order(number:"other"))
        XCTAssertNil(m.copy(try XCTUnwrap(m.permit), current: { newer }, write: { _ in XCTFail() }))
    }
    func testSourceChangedDuringSinkSuppressesOldFeedback() throws {
        let m = try model(); var current: ProfileOrderNumberCopyContext? = try context()
        XCTAssertNil(m.copy(try XCTUnwrap(m.permit), current: { current }, write: { _ in current = nil }))
        XCTAssertNil(m.result)
    }
    func testOldSinkCannotReportIntoReplacementPresentation() throws {
        let m = try model(), c = try context()
        XCTAssertNil(m.copy(try XCTUnwrap(m.permit), current: { c }) { _ in m.suspend(); m.appear(current: c) })
        XCTAssertNil(m.result); XCTAssertNotNil(m.permit)
    }
}

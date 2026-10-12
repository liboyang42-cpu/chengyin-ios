import XCTest
@testable import Questify

@MainActor final class ProfileOrderNumberCopySectionTests: XCTestCase {
    private final class Reader: ProfileReading {
        var identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1)
        var isConfigured = true
        var calls = 0
        func profileOrders() async throws -> [ProfileOrder] { calls += 1; throw APIError.notConfigured }
        func profileOrder(id: Int) async throws -> ProfileOrder { calls += 1; throw APIError.notConfigured }
        func profileParticipants() async throws -> [ProfileParticipant] { calls += 1; throw APIError.notConfigured }
        func profileParticipant(id: Int) async throws -> ProfileParticipant { calls += 1; throw APIError.notConfigured }
        func profileBadges() async throws -> ProfileBadgeWall { calls += 1; throw APIError.notConfigured }
    }
    private func order() throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data(#"{"id":41,"memberId":81,"registrationNo":"000041"}"#.utf8))
    }
    func testConstructingSectionDoesNotWriteClipboardOrStartRead() throws {
        let reader = Reader(); var writes = 0
        _ = ProfileOrderNumberCopySection(order: try order(), requestedID: 41, reader: reader, writeText: { _ in writes += 1 })
        XCTAssertEqual(writes, 0); XCTAssertEqual(reader.calls, 0)
    }
    func testDefaultConcreteLocalWriterRequiresNoOptionalProviderAtExistingDetail() throws {
        let reader = Reader()
        _ = ProfileOrderNumberCopySection(order: try order(), requestedID: 41, reader: reader)
        _ = ProfileOrderDetailView(id: 41, reader: reader)
        XCTAssertEqual(reader.calls, 0)
    }
    func testInjectedWriterReceivesOnlyExactNumberAfterCurrentPermit() throws {
        let reader = Reader(), value = try order(); var copied: [String] = []
        let section = ProfileOrderNumberCopySection(order: value, requestedID: 41, reader: reader, writeText: { copied.append($0) })
        let context = try XCTUnwrap(ProfileOrderNumberCopyContext.capture(order: value, requestedID: 41, reader: reader))
        let model = ProfileOrderNumberCopyModel(context: context); model.appear(current: context)
        XCTAssertEqual(model.copy(try XCTUnwrap(model.permit), current: { context }, write: section.writeText), .copied)
        XCTAssertEqual(copied, ["000041"]); XCTAssertEqual(reader.calls, 0)
    }
    func testWithdrawnOwnerCannotCallInjectedWriterFromOldDetail() throws {
        let reader = Reader(), value = try order(); var copied = 0
        let section = ProfileOrderNumberCopySection(order: value, requestedID: 41, reader: reader, writeText: { _ in copied += 1 })
        let context = try XCTUnwrap(ProfileOrderNumberCopyContext.capture(order: value, requestedID: 41, reader: reader))
        let model = ProfileOrderNumberCopyModel(context: context); model.appear(current: context)
        reader.identity = nil
        XCTAssertNil(model.copy(try XCTUnwrap(model.permit), current: {
            .capture(order: value, requestedID: 41, reader: reader)
        }, write: section.writeText))
        XCTAssertEqual(copied, 0); XCTAssertEqual(reader.calls, 0)
    }
}

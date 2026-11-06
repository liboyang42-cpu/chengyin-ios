import XCTest
@testable import Questify

@MainActor final class ClubProjectLaunchCancelledActivationTests: XCTestCase {
    func testCancelledOldActivationPreservesCurrentTargetAndPermit() async throws {
        let reader = CancelledLaunchReader(), model = ClubProjectLaunchModel()
        let context = reader.context(owner: true)
        let permit = try XCTUnwrap(model.activate(context))
        let result = await model.read(permit, product: .city, reader: reader, editorContextID: { "editor" })
        let target = try XCTUnwrap(result)
        // This actor cannot run the child before cancel, since no suspension intervenes.
        let old = Task { @MainActor in model.activate(context) }
        old.cancel()
        let activated = await old.value
        XCTAssertNil(activated)
        XCTAssertEqual(model.permit(in: context), permit)
        XCTAssertEqual(model.target, target)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(reader.reads, 1)
    }

    func testCancelledStaleIneligibleContextCannotRetireNewVisit() async throws {
        let reader = CancelledLaunchReader(), model = ClubProjectLaunchModel()
        let current = reader.context(owner: true), stale = reader.context(owner: false)
        let permit = try XCTUnwrap(model.activate(current))
        let old = Task { @MainActor in model.activate(stale) }
        old.cancel()
        let activated = await old.value
        XCTAssertNil(activated)
        XCTAssertEqual(model.permit(in: current), permit)
        XCTAssertEqual(reader.reads, 0)
    }

    func testLiveIneligibleActivationStillRetiresTargetAndOldReadPermit() async throws {
        let reader = CancelledLaunchReader(), model = ClubProjectLaunchModel()
        let context = reader.context(owner: true)
        let permit = try XCTUnwrap(model.activate(context))
        _ = await model.read(permit, product: .freeExplore, reader: reader, editorContextID: { "editor" })
        XCTAssertNotNil(model.target)
        XCTAssertNil(model.activate(reader.context(owner: false)))
        XCTAssertNil(model.target)
        XCTAssertNil(model.permit(in: context))
        XCTAssertEqual(model.phase, .idle)
        let stale = await model.read(permit, product: .city, reader: reader, editorContextID: { "editor" })
        XCTAssertNil(stale)
        XCTAssertEqual(reader.reads, 1)
    }
}

@MainActor private final class CancelledLaunchReader: ClubReading {
    let isClubConfigured = true
    let clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var reads = 0
    func record(owner: Bool) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":81,\"isOwner\":\(owner)}".utf8))
    }
    func context(owner: Bool) -> ClubProjectLaunchContext {
        .init(club: record(owner: owner), reader: self, editorContextID: "editor")
    }
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return record(owner: true) }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
}

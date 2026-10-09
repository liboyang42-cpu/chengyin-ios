import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ActivityRequiredClubSelectionViewTests: XCTestCase {
    private final class GateReader: ActivityReading {
        let isConfigured = true
        func activities(page: Int, keyword: String) async throws -> [ActivitySummary] { [] }
        func activityDetail(id: Int) async throws -> ActivityDetailAccess { .clubRequired(clubID: 81, message: "Synthetic gate") }
    }
    private final class ClubReader: ClubReading {
        let isClubConfigured = true
        let clubIdentity = ClubReadIdentity(accountID: 7, epoch: 1)
        var detailReads = 0
        func clubDetail(id: Int) async throws -> ClubRecord { detailReads += 1; throw APIError.notConfigured }
        func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
        func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
        func clubOwned() async throws -> [ClubRecord] { throw APIError.notConfigured }
        func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.notConfigured }
    }
    func testActivityGateDoesNotAutomaticallyOpenClubFactory() {
        var targets: [Int] = []
        let host = UIHostingController(rootView: ActivityDetailView(id: 11, reader: GateReader(),
            requiredClubDestination: { id, _ in targets.append(id); return AnyView(Text("Synthetic club")) }))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertTrue(targets.isEmpty)
    }
    func testReadOnlyHostAdapterRejectsStaleSelectionBeforeBaseRead() async {
        let base = ClubReader()
        let adapter = CoopRelationClubProfileReader(base: base, clubID: 81, isCurrent: { false })
        XCTAssertFalse(adapter.isClubConfigured)
        XCTAssertFalse((adapter as AnyObject) is AppSession)
        do { _ = try await adapter.clubDetail(id: 81); XCTFail("Stale profile read") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(base.detailReads, 0)
    }
    func testExactClubTargetCannotBeSwappedByReadOnlyDestination() async {
        let base = ClubReader()
        let adapter = CoopRelationClubProfileReader(base: base, clubID: 81, isCurrent: { true })
        do { _ = try await adapter.clubDetail(id: 82); XCTFail("Wrong club read") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(base.detailReads, 0)
    }
}

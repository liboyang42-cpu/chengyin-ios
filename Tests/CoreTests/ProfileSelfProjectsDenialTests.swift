import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfProjectsDenialTests: XCTestCase {
    private func make() throws -> (ProjectDenialAccount, ProjectDenialReader, ProfileSelfProjectsScopedReader, ProfileSelfProjectsController) {
        let account = ProjectDenialAccount(), source = ProjectDenialReader()
        source.page = .init(rows: [try JSONDecoder().decode(CreatorContentProject.self,
            from: Data(#"{"id":7,"bizType":"topic","title":"Private project","startTime":"2026-11-05"}"#.utf8))], total: 1)
        let context = try XCTUnwrap(ProfileSelfProjectsContext.capture(memberID: 81, accountReader: account,
            projectsReader: source, owner: account.identity, ownerScope: source.scope, isCurrent: true))
        let reader = ProfileSelfProjectsScopedReader(context: context, accountReader: account, projectsReader: source, isCurrent: { true })
        return (account, source, reader, ProfileSelfProjectsController())
    }
    func testExplicitForbiddenFormsClearPreviousPrivateProjects() async throws {
        let errors: [Error] = [APIError.httpStatus(403), CreatorContentReadFailure.rejected(code: 403, message: nil),
                               CreatorContentReadFailure.rejected(code: 403, message: "Not visible")]
        for error in errors {
            let (_, source, reader, controller) = try make()
            await controller.load(reader: reader)
            XCTAssertEqual(controller.page?.rows.count, 1)
            source.error = error
            await controller.load(reader: reader)
            XCTAssertNil(controller.page)
            XCTAssertEqual(controller.issue, CreatorContentIssue(error))
            XCTAssertFalse(controller.isLoading)
        }
    }
    func testNetworkAndServiceFailurePreserveRowsUntilFreshRead() async throws {
        let errors: [Error] = [APIError.httpStatus(503), URLError(.timedOut),
                               CreatorContentReadFailure.rejected(code: 503, message: "Unavailable")]
        for error in errors {
            let (_, source, reader, controller) = try make()
            await controller.load(reader: reader)
            let row = try XCTUnwrap(controller.page?.rows.first)
            source.error = error
            await controller.load(reader: reader)
            XCTAssertEqual(controller.page?.rows.count, 1)
            XCTAssertFalse(controller.canOpen(row, reader: reader, today: "2026-11-05"))
            source.error = nil; source.page = .init(rows: [], total: 0)
            await controller.load(reader: reader)
            XCTAssertEqual(controller.page?.rows, []); XCTAssertNil(controller.issue)
        }
    }
    func testDeniedReadDoesNotBecomePermanentRetirementOrAutomaticReplay() async throws {
        let (_, source, reader, controller) = try make()
        await controller.load(reader: reader)
        source.error = APIError.httpStatus(403)
        await controller.load(reader: reader)
        XCTAssertEqual(source.reads, 2)
        XCTAssertNil(controller.page)
        source.error = nil
        await controller.load(reader: reader)
        XCTAssertEqual(source.reads, 3)
        XCTAssertEqual(controller.page?.rows.count, 1); XCTAssertNil(controller.issue)
    }
}
@MainActor private final class ProjectDenialAccount: SocialAccountReading {
    let identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    let presentationRevision: UInt64 = 1
    let isConfigured = true, isOfflineExample = false
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    func informationList() async throws -> [SocialInformation] { [] }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}
@MainActor private final class ProjectDenialReader: CreatorContentReading {
    let scope = UUID()
    let isAuthenticated = true, isConfigured = true, isOfflineExample = false
    var page = CreatorContentProjectPage(rows: [], total: 0)
    var error: Error?
    var reads = 0
    func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage {
        reads += 1
        if let error { throw error }
        return page
    }
    func center() async throws -> CreatorContentCenter { throw APIError.invalidRequest }
}

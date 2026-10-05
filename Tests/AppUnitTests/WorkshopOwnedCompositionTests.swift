import XCTest
@testable import Questify

@MainActor final class WorkshopOwnedCompositionTests: XCTestCase {
    private final class Recorder: HTTPTransport {
        var calls = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw WorkshopOwnedIssue.unavailable }
    }
    private func context(account: Int = 7) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://workshop-read.example/native")!, role: "player",
              session: try .init(accountID: account, epoch: 1, namespace: "synthetic", token: "synthetic"))
    }
    func testDefaultsUnavailableWithZeroRequests() throws {
        let c = try context(), r = Recorder()
        XCTAssertNil(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, current: { c }))
        XCTAssertEqual(r.calls, 0)
    }
    func testMissingCurrentApprovalDoesNotMount() throws {
        let c = try context(), r = Recorder(), a = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        XCTAssertNil(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, approval: a, current: { c }))
        XCTAssertEqual(r.calls, 0)
    }
    func testDifferentAccountDoesNotReuseGrant() throws {
        let c = try context(), other = try context(account: 8), r = Recorder(), a = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        XCTAssertNil(WorkshopOwnedComposition.makeBrowser(context: other, api: try APIConfiguration(baseURL: other.baseURL), transport: r, approval: a, currentApproval: { a }, current: { other }))
        XCTAssertEqual(r.calls, 0)
    }
    func testDifferentBaseDoesNotMount() throws {
        let c = try context(), r = Recorder(), a = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        XCTAssertNil(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: URL(string: "https://other.example")!), transport: r, approval: a, currentApproval: { a }, current: { c }))
    }
    func testReplacedOrExpiredApprovalDoesNotMount() throws {
        let c = try context(), r = Recorder(), a = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        let replacement = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        XCTAssertNil(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, approval: a, currentApproval: { replacement }, current: { c }))
        let expired = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantPast)
        XCTAssertNil(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, approval: expired, currentApproval: { expired }, current: { c }))
        XCTAssertEqual(r.calls, 0)
    }
    func testPackageApprovalMustBeSeparateAndCurrent() throws {
        let c = try context(), r = Recorder(), a = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        let p = try WorkshopOwnedPackageReadApproval(context: c, expiresAt: .distantFuture)
        let blocked = try XCTUnwrap(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, approval: a, currentApproval: { a }, current: { c }, packageApproval: p))
        XCTAssertNil(blocked.packageBrowser)
        let enabled = try XCTUnwrap(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, approval: a, currentApproval: { a }, current: { c }, packageApproval: p, currentPackageApproval: { p }))
        XCTAssertNotNil(enabled.packageBrowser); XCTAssertEqual(r.calls, 0)
        enabled.invalidate(); XCTAssertEqual(enabled.packageBrowser?.phase, .invalidated)
    }
    func testApprovedFactoryDoesNotAutomaticallyFetchAndInvalidationIsFinal() throws {
        let c = try context(), r = Recorder(), a = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        let browser = try XCTUnwrap(WorkshopOwnedComposition.makeBrowser(context: c, api: try APIConfiguration(baseURL: c.baseURL), transport: r, approval: a, currentApproval: { a }, current: { c }))
        XCTAssertEqual(browser.phase, .idle); XCTAssertEqual(r.calls, 0); XCTAssertNil(browser.packageBrowser)
        browser.invalidate(); XCTAssertEqual(browser.phase, .invalidated)
    }
}

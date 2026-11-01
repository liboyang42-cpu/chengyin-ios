import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class H5ShellBindingTests: XCTestCase {
    private let origin = "https://origin.example"
    private let ticket = "ticket-kept-value"

    func testBlankAndRejectedHostsStayNil() {
        for host in [nil, "", " ", "http://origin.example", "https://user@origin.example",
                     "https://origin.example?q=1", "https://origin.example#part", "https://origin.example/shell",
                     "https://origin.example/"] {
            XCTAssertNil(H5ShellBinding.keptOrigin(host, ticket: ticket))
        }
        XCTAssertNil(H5ShellBinding.keptOrigin("https://ticket-kept-value.example", ticket: ticket))
    }

    func testHttpsOriginIsKeptWhenTheTicketIsAbsentFromIt() {
        XCTAssertEqual(H5ShellBinding.keptOrigin("  \(origin)  ", ticket: ticket), origin)
    }

    func testOpenRunsOnceOnlyWhenTheShellEqualsTheKeptOrigin() {
        var parent = H5ShellParentFlow(requestID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        let shell = URL(string: origin)
        let opened = H5ShellBinding.openExistingShell(parentOrigin: origin, shellURL: shell,
                                                      launchTicket: ticket, parent: &parent)
        XCTAssertEqual(opened?.url?.absoluteString, origin)
        XCTAssertTrue(parent.shellLoaded)
        XCTAssertEqual(parent.shellLoaded, opened != nil)
    }

    func testMissingFieldDoesNotOpenOrFillAValue() {
        var parent = H5ShellParentFlow(requestID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        XCTAssertNil(H5ShellBinding.openExistingShell(parentOrigin: nil, shellURL: URL(string: origin),
                                                      launchTicket: ticket, parent: &parent))
        XCTAssertNil(H5ShellBinding.openExistingShell(parentOrigin: origin, shellURL: nil,
                                                      launchTicket: ticket, parent: &parent))
        XCTAssertNil(H5ShellBinding.openExistingShell(parentOrigin: origin, shellURL: URL(string: origin),
                                                      launchTicket: nil, parent: &parent))
        XCTAssertNil(H5ShellBinding.openExistingShell(parentOrigin: origin, shellURL: URL(string: origin),
                                                      launchTicket: " ", parent: &parent))
        XCTAssertNil(H5ShellBinding.openExistingShell(parentOrigin: origin,
                                                      shellURL: URL(string: origin + "/shell"),
                                                      launchTicket: ticket, parent: &parent))
        XCTAssertFalse(parent.shellLoaded)
    }
}

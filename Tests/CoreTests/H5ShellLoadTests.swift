import XCTest
@testable import QuestifyCore

final class H5ShellLoadTests: XCTestCase {
    func testShellPostKeepsTheNonceAndRejectsAnotherHost() throws {
        let launch = try XCTUnwrap(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce1", mainToken: nil))
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        let request = try XCTUnwrap(H5ShellLoad.request(shellURL: shell, launch: launch))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: request.httpBody ?? Data(), encoding: .utf8), "nonce=nonce1")
        XCTAssertFalse((request.httpBody ?? Data()).contains("token".data(using: .utf8)!))
        let other = try XCTUnwrap(URL(string: "https://evil.example/shell"))
        XCTAssertNil(H5ShellLoad.request(shellURL: other, launch: launch))
        XCTAssertFalse(H5ShellLoad.allowsNavigation(to: other, shellURL: shell))
        XCTAssertTrue(H5ShellLoad.allowsNavigation(to: shell, shellURL: shell))
    }
}

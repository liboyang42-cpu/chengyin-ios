import XCTest
@testable import Questify

@MainActor final class SocialMemberActionAppTests: XCTestCase {
    func testNormalSessionFactoryHasNoMemberWriteGrants() {
        let dependencies = NativeRuntimeDependencies.dormant
        XCTAssertTrue(dependencies.socialMemberActionApprovals.isEmpty)
        let session = AppSession(runtimeDependencies: dependencies)
        XCTAssertEqual(session.socialActionAccess.availability, .disabled)
        XCTAssertEqual(session.socialActionCoordinator.availability(for: .toggleFollow, target: .member(82)), .disabled)
        XCTAssertEqual(session.socialActionCoordinator.availability(for: .startChat, target: .member(82)), .disabled)
        XCTAssertEqual(session.socialActionCoordinator.availability(for: .communityComment(text: "hello", requestID: "abcdefghijklmnop"), target: .post(82)), .disabled)
    }
}

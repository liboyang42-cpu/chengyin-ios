import XCTest
@testable import QuestifyCore

final class SessionOperationGateTests: XCTestCase {
    func testClosingUntouchedLoginDoesNotCancelPendingBootstrap() {
        var gate=SessionOperationGate()
        let bootstrap=gate.begin(.bootstrap)
        XCTAssertFalse(gate.cancelLogin())
        XCTAssertTrue(gate.isCurrent(bootstrap))
        XCTAssertEqual(gate.activeKind,.bootstrap)
        gate.finish(bootstrap)
        XCTAssertNil(gate.activeKind)
    }
    func testClosingActiveLoginInvalidatesItsCompletion() {
        var gate=SessionOperationGate();let login=gate.begin(.login)
        XCTAssertTrue(gate.cancelLogin());XCTAssertFalse(gate.isCurrent(login));XCTAssertNil(gate.activeKind)
    }
    func testOldCompletionCannotFinishNewOperation() {
        var gate=SessionOperationGate();let old=gate.begin(.bootstrap)
        let new=gate.begin(.login);gate.finish(old)
        XCTAssertFalse(gate.isCurrent(old));XCTAssertTrue(gate.isCurrent(new));XCTAssertEqual(gate.activeKind,.login)
    }
    func testLogoutInvalidatesBootstrapAndLogin() {
        for kind in [SessionOperationGate.Kind.bootstrap,.login] {
            var gate=SessionOperationGate();let old=gate.begin(kind);gate.invalidate()
            XCTAssertFalse(gate.isCurrent(old));XCTAssertNil(gate.activeKind)
        }
    }
}

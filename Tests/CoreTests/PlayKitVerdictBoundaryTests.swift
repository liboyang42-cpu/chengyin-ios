import XCTest
@testable import QuestifyCore

final class PlayKitVerdictBoundaryTests: XCTestCase {
    private func projection(_ kind:PlayKitScreenKind,_ text:String)throws->PlayKitScreenProjection {
        .init(kind:kind,segment:try JSONDecoder().decode(PlayWireValue.self,from:Data(text.utf8)))
    }
    func testStopwatchAttemptCapDoesNotFabricateFailureBeforeFirstAttempt() throws {
        let value=try projection(.stopwatch,#"{"tries":3,"started":false,"submitted":false,"passed":false}"#)
        XCTAssertNil(value.reportedPass);XCTAssertFalse(value.complete)
    }
    func testStopwatchActualFailedAttemptCanBeShownWhileRetryRemainsOpen() throws {
        let value=try projection(.stopwatch,#"{"tries":3,"attempts":1,"submitted":false,"passed":false}"#)
        XCTAssertEqual(value.reportedPass,false);XCTAssertFalse(value.complete)
    }
    func testTypeInCapWithoutAttemptDoesNotBecomeAResult() throws {
        XCTAssertNil(try projection(.typeIn,#"{"tries":3,"attempts":0,"passed":false}"#).reportedPass)
    }
    func testPhotoDegradationNeverBecomesPassOrFailureEvenWithFlags() throws {
        XCTAssertNil(try projection(.photoCheck,#"{"tries":1,"degraded":true,"flagged":true,"passed":false}"#).reportedPass)
        XCTAssertNil(try projection(.photoCheck,#"{"tries":1,"degraded":true,"passed":true}"#).reportedPass)
    }
    func testPhotoFallbackDoesNotMislabelItsFalsePassedFieldAsFailure() throws {
        let value=try projection(.photoCheck,#"{"tries":3,"flagged":true,"passed":false,"fallback":"pass"}"#)
        XCTAssertNil(value.reportedPass);XCTAssertTrue(value.complete)
    }
    func testPhotoActualRetakeDecisionStillShowsFailure() throws {
        XCTAssertEqual(try projection(.photoCheck,#"{"tries":1,"flagged":false,"degraded":false,"passed":false}"#).reportedPass,false)
    }
}

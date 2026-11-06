import XCTest
@testable import QuestifyCore

final class TestFlightInternalAndExternalSmokeMatrixContractTests: XCTestCase {
    func testCanonicalSixJourneysPassSmokeMatrix() {
        let evaluation = TestFlightInternalAndExternalSmokeMatrixContract.evaluate()
        XCTAssertEqual(evaluation.totalJourneys, 6)
        XCTAssertEqual(evaluation.compliantJourneys, 6)
        XCTAssertTrue(evaluation.isTestFlightSmokeReady)

        let ids = TestFlightInternalAndExternalSmokeMatrixContract.canonicalJourneys.map(\.id)
        XCTAssertEqual(ids, [
            "tf-smoke-01-auth-and-session-gate",
            "tf-smoke-02-city-roam-and-stamp-unlock",
            "tf-smoke-03-story-walking-and-durable-recovery",
            "tf-smoke-04-npc-chat-and-tts-audio",
            "tf-smoke-05-merchant-store-and-apply-wizard",
            "tf-smoke-06-club-enrollment-and-settlement",
        ])
    }

    func testMissingAutomatedUITestTwinFailsSmokeMatrix() {
        var journeys = TestFlightInternalAndExternalSmokeMatrixContract.canonicalJourneys
        journeys[0] = TestFlightSmokeJourneyCheck(
            id: journeys[0].id,
            journeyTitle: journeys[0].journeyTitle,
            hasAutomatedUITestTwin: false,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        )

        let evaluation = TestFlightInternalAndExternalSmokeMatrixContract.evaluate(journeys: journeys)
        XCTAssertEqual(evaluation.totalJourneys, 6)
        XCTAssertEqual(evaluation.compliantJourneys, 5)
        XCTAssertFalse(evaluation.isTestFlightSmokeReady)
    }

    func testUnverifiedCrashAndBlankScreenGuardFailsSmokeMatrix() {
        var journeys = TestFlightInternalAndExternalSmokeMatrixContract.canonicalJourneys
        journeys[2] = TestFlightSmokeJourneyCheck(
            id: journeys[2].id,
            journeyTitle: journeys[2].journeyTitle,
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: false,
            verifiesFailClosedOrAllowlistedWrites: true
        )

        let evaluation = TestFlightInternalAndExternalSmokeMatrixContract.evaluate(journeys: journeys)
        XCTAssertEqual(evaluation.totalJourneys, 6)
        XCTAssertEqual(evaluation.compliantJourneys, 5)
        XCTAssertFalse(evaluation.isTestFlightSmokeReady)
    }

    func testUnverifiedWriteGateFailsSmokeMatrix() {
        var journeys = TestFlightInternalAndExternalSmokeMatrixContract.canonicalJourneys
        journeys[4] = TestFlightSmokeJourneyCheck(
            id: journeys[4].id,
            journeyTitle: journeys[4].journeyTitle,
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: false
        )

        let evaluation = TestFlightInternalAndExternalSmokeMatrixContract.evaluate(journeys: journeys)
        XCTAssertEqual(evaluation.totalJourneys, 6)
        XCTAssertEqual(evaluation.compliantJourneys, 5)
        XCTAssertFalse(evaluation.isTestFlightSmokeReady)
    }
}

import XCTest
@testable import QuestifyCore

final class PlayKitSensorStageTests: XCTestCase {
    private func readyQuiet(seconds: Double = 1) -> PlayKitQuietRun {
        var run = PlayKitQuietRun(seconds: seconds); run.calibrate()
        for index in 0...20 { run.ingest(peak: 0.04, timestamp: Double(index) / 10) }
        XCTAssertEqual(run.phase, .ready); return run
    }
    private func readyShout(seconds: Double = 1) -> PlayKitShoutRun {
        var run = PlayKitShoutRun(seconds: seconds); run.calibrate()
        for index in 0...20 { run.ingest(peak: 0.04, timestamp: Double(index) / 10) }
        XCTAssertEqual(run.phase, .ready); return run
    }
    private func readyBall(goal: Int = 3) -> PlayKitBallRun {
        var run = PlayKitBallRun(goal: goal, limitSeconds: 0); run.calibrate()
        for index in 0...12 { run.ingest(x: 0, y: 0, timestamp: Double(index) / 10, randomUnit: 0.5) }
        XCTAssertEqual(run.phase, .ready); return run
    }

    func testEmptyStreamsCannotCalibrateOrComplete() {
        var quiet = PlayKitQuietRun(seconds: 1); quiet.calibrate()
        var shout = PlayKitShoutRun(seconds: 1); shout.calibrate()
        var ball = PlayKitBallRun(goal: 1, limitSeconds: 1); ball.calibrate()
        quiet.beginAfterAcknowledgement(); shout.beginAfterAcknowledgement(); ball.beginAfterAcknowledgement()
        XCTAssertEqual(quiet.phase, .calibrating); XCTAssertEqual(shout.phase, .calibrating); XCTAssertEqual(ball.phase, .calibrating)
        let continuity = PlayKitSensorContinuity(kind: .soundPeak, now: 10)
        XCTAssertTrue(continuity.expired(now: 13.01))
    }
    func testReadyDoesNotEarnTimeBeforeStartAcknowledgement() {
        var quiet = readyQuiet(), shout = readyShout(), ball = readyBall()
        quiet.ingest(peak: 0, timestamp: 10); shout.ingest(peak: 1, timestamp: 10)
        ball.ingest(x: -9.8, y: 9.8, timestamp: 10, randomUnit: 0.5)
        XCTAssertEqual(quiet.phase, .ready); XCTAssertEqual(quiet.heldSeconds, 0)
        XCTAssertEqual(shout.phase, .ready); XCTAssertEqual(shout.heldSeconds, 0)
        XCTAssertEqual(ball.phase, .ready); XCTAssertEqual(ball.hits, 0)
    }
    func testQuietFirstLoudSampleEndsMeasurementWithoutAwardingTime() {
        var run = readyQuiet(); run.beginAfterAcknowledgement()
        run.ingest(peak: 0.9, timestamp: 3)
        XCTAssertEqual(run.phase, .measured); XCTAssertTrue(run.exceeded); XCTAssertEqual(run.heldSeconds, 0)
    }
    func testQuietFreshSilenceCanMeasureButGapInterrupts() {
        var run = readyQuiet(); run.beginAfterAcknowledgement()
        for index in 0...12 { run.ingest(peak: 0.02, timestamp: 3 + Double(index) / 10) }
        XCTAssertEqual(run.phase, .measured); XCTAssertFalse(run.exceeded)
        var interrupted = readyQuiet(); interrupted.beginAfterAcknowledgement()
        interrupted.ingest(peak: 0.02, timestamp: 3); interrupted.ingest(peak: 0.02, timestamp: 3.5)
        XCTAssertEqual(interrupted.phase, .interrupted); XCTAssertEqual(interrupted.heldSeconds, 0)
    }
    func testCalibrationOutlierDoesNotSetBaselineToMaximum() {
        var run = PlayKitShoutRun(seconds: 1); run.calibrate()
        for index in 0...20 { run.ingest(peak: index == 4 ? 0.95 : 0.1, timestamp: Double(index) / 10) }
        XCTAssertEqual(run.warningThreshold, 0.16, accuracy: 0.00001)
        XCTAssertEqual(run.loudThreshold, 0.25, accuracy: 0.00001)
    }
    func testShoutRequiresContinuouslyLoudIntervalsAndResetsOnDrop() {
        var run = readyShout(); run.beginAfterAcknowledgement()
        for index in 0...5 { run.ingest(peak: 0.9, timestamp: 3 + Double(index) / 10) }
        XCTAssertGreaterThan(run.heldSeconds, 0)
        run.ingest(peak: run.loudThreshold, timestamp: 3.6)
        XCTAssertEqual(run.heldSeconds, 0); XCTAssertFalse(run.loud)
        run.ingest(peak: 0.9, timestamp: 3.7)
        XCTAssertEqual(run.heldSeconds, 0, "The first loud sample cannot earn the preceding quiet interval")
        for index in 1...12 { run.ingest(peak: 0.9, timestamp: 3.7 + Double(index) / 10) }
        XCTAssertEqual(run.phase, .measured); XCTAssertEqual(run.heldSeconds, 1)
    }
    func testShoutGapAndBackgroundDiscardUnfinishedMeasurement() {
        var run = readyShout(); run.beginAfterAcknowledgement()
        run.ingest(peak: 1, timestamp: 3); run.ingest(peak: 1, timestamp: 3.1); run.ingest(peak: 1, timestamp: 4)
        XCTAssertEqual(run.phase, .interrupted); XCTAssertEqual(run.heldSeconds, 0)
        var other = readyShout(); other.beginAfterAcknowledgement(); other.ingest(peak: 1, timestamp: 3)
        other.interrupt(); other.ingest(peak: 1, timestamp: 3.1)
        XCTAssertEqual(other.phase, .interrupted); XCTAssertEqual(other.heldSeconds, 0)
    }
    func testShoutInvalidAndDuplicateSamplesCannotEarnTime() {
        var run = readyShout(); run.beginAfterAcknowledgement()
        run.ingest(peak: 1, timestamp: 3); run.ingest(peak: 1, timestamp: 3)
        run.ingest(peak: .nan, timestamp: 3.1); run.ingest(peak: 2, timestamp: 3.1)
        XCTAssertEqual(run.heldSeconds, 0); XCTAssertEqual(run.phase, .running)
    }
    func testCompassWraparoundAndContinuousNeedleUseShortArc() {
        XCTAssertEqual(PlayKitCompassRun.angleDifference(359, 1), 2)
        XCTAssertEqual(PlayKitCompassRun.normalized(-1), 359)
        XCTAssertEqual(PlayKitCompassRun.continuous(1, previous: 359), 361)
        XCTAssertEqual(PlayKitCompassRun.continuous(359, previous: 1), -1)
    }
    func testCompassRequiresHoldNotOneAlignedFrame() {
        var run = PlayKitCompassRun(target: 0, tolerance: 10, holdSeconds: 1); run.begin()
        run.ingest(bearing: 359, accuracy: 3, timestamp: 0)
        XCTAssertNil(run.submittedBearing); XCTAssertEqual(run.heldSeconds, 0)
        for index in 1...12 { run.ingest(bearing: 359, accuracy: 3, timestamp: Double(index) / 10) }
        XCTAssertEqual(run.phase, .measured); XCTAssertEqual(run.submittedBearing, 359)
    }
    func testCompassReportsActualNorthNotTargetFallback() {
        var run = PlayKitCompassRun(target: 8, tolerance: 10, holdSeconds: 1); run.begin()
        for index in 0...12 { run.ingest(bearing: 0, accuracy: 2, timestamp: Double(index) / 10) }
        XCTAssertEqual(run.submittedBearing, 0)
    }
    func testCompassMisalignmentAndPoorAccuracyClearHold() {
        var run = PlayKitCompassRun(target: 0, tolerance: 10, holdSeconds: 1); run.begin()
        for index in 0...4 { run.ingest(bearing: 1, accuracy: 2, timestamp: Double(index) / 10) }
        XCTAssertGreaterThan(run.heldSeconds, 0)
        run.ingest(bearing: 40, accuracy: 2, timestamp: 0.5)
        XCTAssertFalse(run.aligned); XCTAssertEqual(run.heldSeconds, 0)
        run.ingest(bearing: 1, accuracy: 2, timestamp: 0.6)
        run.ingest(bearing: 1, accuracy: 2, timestamp: 0.7)
        run.ingest(bearing: 1, accuracy: 30, timestamp: 0.8)
        XCTAssertTrue(run.lowAccuracy); XCTAssertEqual(run.heldSeconds, 0); XCTAssertNil(run.submittedBearing)
    }
    func testCompassStalledStreamCannotEarnHold() {
        var run = PlayKitCompassRun(target: 0, tolerance: 10, holdSeconds: 1); run.begin()
        run.ingest(bearing: 1, accuracy: 2, timestamp: 1)
        run.ingest(bearing: 1, accuracy: 2, timestamp: 5)
        XCTAssertEqual(run.phase, .interrupted); XCTAssertNil(run.submittedBearing)
    }
    func testCompassOnlyMeasuresWhenRoundedPayloadStillFitsTolerance() {
        var run = PlayKitCompassRun(target: 1.2, tolerance: 1, holdSeconds: 1); run.begin()
        for index in 0...20 { run.ingest(bearing: 0.21, accuracy: 0.1, timestamp: Double(index) / 10) }
        XCTAssertEqual(run.phase, .running); XCTAssertNil(run.submittedBearing)
    }
    func testContinuityRejectsWrongKindStaleFutureAndDuplicateSamples() {
        var run = PlayKitSensorContinuity(kind: .soundPeak, now: 10)
        XCTAssertFalse(run.accept(.acceleration(x: 0, y: 0, z: 9.8, timestamp: 10), now: 10))
        XCTAssertFalse(run.accept(.soundPeak(0, timestamp: 9.9), now: 10))
        XCTAssertFalse(run.accept(.soundPeak(0, timestamp: 11), now: 10))
        XCTAssertTrue(run.accept(.soundPeak(0, timestamp: 10), now: 10))
        XCTAssertFalse(run.accept(.soundPeak(0, timestamp: 10), now: 10.1))
        XCTAssertFalse(run.expired(now: 10.2)); XCTAssertTrue(run.expired(now: 10.3))
    }
    func testContinuityRejectsNonfiniteSamplesAndTimeRegression() {
        var run = PlayKitSensorContinuity(kind: .heading, now: 1)
        XCTAssertFalse(run.accept(.heading(.nan, accuracy: 1, timestamp: 1), now: 1))
        XCTAssertFalse(run.accept(.heading(1, accuracy: -1, timestamp: 1), now: 1))
        XCTAssertFalse(run.accept(.heading(1, accuracy: 1, timestamp: 1), now: .nan))
        XCTAssertTrue(run.expired(now: 0))
    }
    func testBallRequiresRealTiltAndCountsPhysicalWallContacts() {
        var run = readyBall(goal: 1); run.beginAfterAcknowledgement()
        for index in 0...30 { run.ingest(x: 0, y: 0, timestamp: 2 + Double(index) * 0.016, randomUnit: 0.5) }
        XCTAssertEqual(run.hits, 0); XCTAssertEqual(run.x, 150); XCTAssertEqual(run.y, 210)
        for index in 31...300 { run.ingest(x: -9.8, y: 0, timestamp: 2 + Double(index) * 0.016, randomUnit: 0.5) }
        XCTAssertEqual(run.phase, .measured); XCTAssertGreaterThanOrEqual(run.hits, 1)
    }
    func testBallGapInterruptsInsteadOfRunningWithLastTilt() {
        var run = readyBall(); run.beginAfterAcknowledgement()
        run.ingest(x: -9.8, y: 0, timestamp: 3, randomUnit: 0.5)
        run.ingest(x: -9.8, y: 0, timestamp: 4, randomUnit: 0.5)
        XCTAssertEqual(run.phase, .interrupted); XCTAssertEqual(run.hits, 0)
    }
    func testQuietReviewDetailConvertsSecondsExactlyOnce() throws {
        var run = readyQuiet(); run.beginAfterAcknowledgement()
        XCTAssertNil(run.reviewDetail)
        run.ingest(peak: 0.02, timestamp: 3)
        run.ingest(peak: 0.02, timestamp: 3.087)
        run.ingest(peak: 0.9, timestamp: 3.1)
        let detail = try XCTUnwrap(run.reviewDetail)
        XCTAssertEqual(detail["heldSeconds"]?.double ?? -1, 0.087, accuracy: 0.000001)
        XCTAssertNil(detail["heldMs"])
        let wire = try PlayKitActionCatalog.payload(kind: "quietHold", action: "SUBMIT_QUIET_HOLD", detail: detail)
        XCTAssertEqual(wire, ["heldMs": .integer(87)])
        XCTAssertThrowsError(try PlayKitActionCatalog.payload(kind: "quietHold", action: "SUBMIT_QUIET_HOLD", detail: wire))
    }
    func testShoutReviewDetailRetainsMilliseconds() throws {
        let detail: [String: PlayWireValue] = ["heldMs": .integer(1250)]
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "shout", action: "SUBMIT_SHOUT", detail: detail), detail)
    }
    @MainActor func testDefaultProviderHasNoGrantedSensor() async {
        let provider = PlayKitDormantSensorProvider()
        XCTAssertTrue(provider.supported.isEmpty)
        var count = 0
        do {
            for try await _ in provider.samples(.soundPeak) { count += 1 }
            XCTFail("A disabled provider must report the missing grant")
        } catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        XCTAssertEqual(count, 0)
    }
}

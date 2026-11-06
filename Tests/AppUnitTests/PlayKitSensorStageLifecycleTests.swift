import Foundation
import XCTest
@testable import Questify

/// Extends the existing RuntimeAppTestSensor protocol-fake pattern with explicit
/// authorization and stream control. No OS permission or device is accessed.
@MainActor private final class StageLifecycleSensor: PlayKitSensorProviding, PlayKitSensorAuthorizing {
    let supported: Set<PlayKitSensorKind> = [.heading, .soundPeak, .acceleration]
    var suspendAuthorization = false
    var authorizationError: PlayKitSensorError?
    private(set) var prepares = 0
    private(set) var authorizationReturns = 0
    private(set) var cancellations = 0
    private(set) var streams: [AsyncThrowingStream<PlayKitSensorSample, Error>.Continuation] = []
    private var authorizations: [CheckedContinuation<Void, Error>] = []
    func prepare(_ kind: PlayKitSensorKind) async throws {
        prepares += 1
        defer { authorizationReturns += 1 }
        if let authorizationError { throw authorizationError }
        if suspendAuthorization {
            try await withCheckedThrowingContinuation { authorizations.append($0) }
        }
    }
    func samples(_ kind: PlayKitSensorKind) -> AsyncThrowingStream<PlayKitSensorSample, Error> {
        AsyncThrowingStream { streams.append($0) }
    }
    // Deliberately does not release a suspended permission callback or complete a
    // stream: the real stage must reject late work with its own attempt/token.
    func cancel() { cancellations += 1 }
    func authorizeOldest() { if !authorizations.isEmpty { authorizations.removeFirst().resume() } }
    func finish() {
        for pending in authorizations { pending.resume(throwing: CancellationError()) }
        authorizations = []
        for stream in streams { stream.finish() }
    }
    func heading(_ value: Double, stream: Int) {
        streams[stream].yield(.heading(value, accuracy: 1, timestamp: ProcessInfo.processInfo.systemUptime))
    }
}

@MainActor final class PlayKitSensorStageLifecycleTests: XCTestCase {
    private enum WaitFailure: Error { case timedOut }
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("In-memory stage did not reach the expected state", file: file, line: line)
        throw WaitFailure.timedOut
    }
    private func compass(_ sensor: StageLifecycleSensor) -> PlayKitSensorStageModel {
        .init(kind: .compass, segment: .object(["bearing": .integer(90), "holdSeconds": .integer(1)]),
              provider: sensor, revisionIdentity: "7:1")
    }
    func testPermissionDeniedNeverStartsSamplesAndCanRetryExplicitly() async throws {
        let sensor = StageLifecycleSensor(); defer { sensor.finish() }
        sensor.authorizationError = .permissionDenied
        let stage = compass(sensor); defer { stage.interrupt(.interrupted) }
        stage.begin(active: true)
        try await waitUntil { stage.phase == .interrupted }
        XCTAssertEqual(stage.issue, .permissionDenied); XCTAssertTrue(sensor.streams.isEmpty); XCTAssertNil(stage.payload)
        sensor.authorizationError = nil
        stage.begin(active: true)
        try await waitUntil { sensor.streams.count == 1 }
        XCTAssertEqual(stage.phase, .running); XCTAssertNil(stage.issue); XCTAssertNil(stage.payload)
    }
    func testInterruptedPermissionCallbackCannotStartOldStream() async throws {
        let sensor = StageLifecycleSensor(); defer { sensor.finish() }
        sensor.suspendAuthorization = true
        let stage = compass(sensor); defer { stage.interrupt(.interrupted) }
        stage.begin(active: true)
        try await waitUntil { sensor.prepares == 1 }
        let original = stage.attempt
        stage.interrupt(.interrupted)
        sensor.authorizeOldest()
        // A second explicit start provides an observable barrier after the old callback.
        sensor.suspendAuthorization = false
        stage.begin(active: true)
        try await waitUntil { sensor.streams.count == 1 && sensor.authorizationReturns == 2 }
        XCTAssertNotEqual(stage.attempt, original)
        XCTAssertEqual(sensor.prepares, 2); XCTAssertEqual(sensor.streams.count, 1)
        XCTAssertFalse(stage.startAfterAcknowledgement(attempt: original, revisionIdentity: "7:1"))
        XCTAssertNil(stage.payload)
    }
    func testOldStreamCannotContaminateReplacementAttempt() async throws {
        let sensor = StageLifecycleSensor(); defer { sensor.finish() }
        let stage = compass(sensor); defer { stage.interrupt(.interrupted) }
        stage.begin(active: true); try await waitUntil { sensor.streams.count == 1 }
        stage.interrupt(.interrupted)
        stage.begin(active: true); try await waitUntil { sensor.streams.count == 2 }
        sensor.heading(270, stream: 0)
        sensor.streams[0].finish(throwing: PlayKitSensorError.permissionDenied)
        sensor.heading(90, stream: 1)
        try await waitUntil { stage.compass.heading == 90 }
        XCTAssertEqual(stage.phase, .running); XCTAssertNil(stage.issue)
        XCTAssertNil(stage.payload); XCTAssertEqual(stage.compass.heldSeconds, 0)
    }
    func testMeasuredEvidenceIsRemovedByInterruption() async throws {
        let sensor = StageLifecycleSensor(); defer { sensor.finish() }
        let stage = compass(sensor); defer { stage.interrupt(.interrupted) }
        stage.begin(active: true); try await waitUntil { sensor.streams.count == 1 }
        // Real stage ingestion and Core continuity use monotonic time. This is
        // synthetic heading evidence, not a claim of actual compass accuracy.
        for _ in 0..<35 {
            if stage.phase == .measured { break }
            sensor.heading(90, stream: 0)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(stage.phase, .measured)
        XCTAssertEqual(stage.payload?["bearing"], .integer(90))
        let attempt = stage.attempt
        stage.interrupt(.interrupted)
        XCTAssertNotEqual(stage.attempt, attempt)
        XCTAssertEqual(stage.phase, .interrupted); XCTAssertNil(stage.payload)
        XCTAssertNil(stage.compass.heading); XCTAssertEqual(stage.compass.heldSeconds, 0)
        XCTAssertFalse(stage.startAfterAcknowledgement(attempt: attempt, revisionIdentity: "7:1"))
    }
    func testRevisionRestoresCurrentConfigurationAndRejectsOldAuthorization() async throws {
        let sensor = StageLifecycleSensor(); defer { sensor.finish() }
        sensor.suspendAuthorization = true
        let stage = PlayKitSensorStageModel(kind: .quietHold, segment: .object(["seconds": .integer(15)]), provider: sensor, revisionIdentity: "7:1")
        defer { stage.interrupt(.interrupted) }
        stage.begin(active: true); try await waitUntil { sensor.prepares == 1 }
        let old = stage.attempt
        stage.updateRevision("7:2", segment: .object(["seconds": .integer(8), "goal": .integer(12), "timed": .bool(true), "bearing": .integer(180), "tolerance": .integer(4), "holdSeconds": .integer(2)]))
        sensor.authorizeOldest()
        XCTAssertEqual(stage.phase, .interrupted); XCTAssertNotEqual(stage.attempt, old)
        XCTAssertEqual(stage.quiet.targetSeconds, 8); XCTAssertEqual(stage.shout.targetSeconds, 8)
        XCTAssertEqual(stage.ball.goal, 12); XCTAssertEqual(stage.ball.limitSeconds, 8)
        XCTAssertEqual(stage.compass.target, 180); XCTAssertEqual(stage.compass.tolerance, 4); XCTAssertEqual(stage.compass.holdSeconds, 2)
        XCTAssertNil(stage.payload)
        XCTAssertFalse(stage.startAfterAcknowledgement(attempt: old, revisionIdentity: "7:2"))
        sensor.suspendAuthorization = false; stage.begin(active: true)
        try await waitUntil { sensor.streams.count == 1 && sensor.authorizationReturns == 2 }
        XCTAssertEqual(stage.phase, .calibrating); XCTAssertEqual(sensor.prepares, 2)
    }
    func testInactiveEntryAndSameRevisionDoNotStartOrResetAnAttempt() {
        let sensor = StageLifecycleSensor(); defer { sensor.finish() }
        let stage = compass(sensor); defer { stage.interrupt(.interrupted) }
        let original = stage.attempt
        stage.begin(active: false)
        XCTAssertEqual(stage.phase, .idle); XCTAssertEqual(stage.attempt, original)
        XCTAssertEqual(sensor.prepares, 0); XCTAssertTrue(sensor.streams.isEmpty)
        stage.updateRevision("7:1", segment: .object(["bearing": .integer(180)]))
        XCTAssertEqual(stage.attempt, original); XCTAssertEqual(stage.compass.target, 90)
    }
}

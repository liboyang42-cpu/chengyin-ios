import Foundation
import AVFoundation
import UIKit
import XCTest
@testable import Questify
@MainActor private final class OwnerAudioMemoryPlayer: OwnMediaAudioMemoryPlaying {
    var delegate: (any AVAudioPlayerDelegate)?
    var duration: TimeInterval = 30, currentTime: TimeInterval = 0, ownMediaSampleRate: Double = 44_100
    var numberOfChannels = 2, prepared = 0, played = 0, paused = 0, stopped = 0
    var prepareOK = true, playOK = true, onPrepare: (() -> Void)?, onPlay: (() -> Void)?
    func prepareToPlay() -> Bool { prepared += 1; onPrepare?(); return prepareOK }
    func play() -> Bool { played += 1; onPlay?(); return playOK }
    func pause() { paused += 1 }
    func stop() { stopped += 1 }
}
@MainActor private final class OwnerAudioDeviceFixture {
    let notes = NotificationCenter()
    var current = true, permits = true, made = 0, player = OwnerAudioMemoryPlayer(), events: [OwnMediaAudioPreviewDeviceEvent] = []
    let bytes = Data([82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69]) // Header-only synthetic data, never native-decoded.
    lazy var device = OwnMediaAudioPreviewDevice(dependencies: .init(notifications: notes, makePlayer: { [unowned self] _ in made += 1; return player }, permitsPlayback: { [unowned self] in permits }))
    func prepare() throws { _ = try device.prepare(bytes, current: { [unowned self] in current }, event: { [unowned self] in events.append($0) }) }
}
@MainActor final class OwnMediaAudioPreviewDeviceTests: XCTestCase {
    func testPrepareOnlyHoldsMemoryAndDoesNotPlayOrPrepareHardware() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); XCTAssertEqual(f.made, 1); XCTAssertEqual(f.player.prepared, 0); XCTAssertEqual(f.player.played, 0); f.device.stop()
    }
    func testExplicitPlayPauseSeekAndStopOnlyTouchOwnedPlayer() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); try f.device.play(); f.device.pause(); try f.device.seek(12)
        XCTAssertEqual(f.player.played, 1); XCTAssertEqual(f.player.paused, 1); XCTAssertEqual(f.device.position, 12)
        f.device.stop(); XCTAssertEqual(f.player.stopped, 1); XCTAssertNil(f.player.delegate)
    }
    func testBadHeaderCannotReachPlayerFactory() throws {
        let f = OwnerAudioDeviceFixture(); XCTAssertThrowsError(try f.device.prepare(Data("html".utf8), current: { true }, event: { _ in })); XCTAssertEqual(f.made, 0)
    }
    func testInvalidDecodedMetadataFailsBeforeAnyPlay() throws {
        for mode in 0..<6 { let f = OwnerAudioDeviceFixture()
            if mode == 0 { f.player.duration = .infinity }; if mode == 1 { f.player.duration = TimeInterval(Int.max) }; if mode == 2 { f.player.duration = 0 }
            if mode == 3 { f.player.numberOfChannels = 0 }; if mode == 4 { f.player.ownMediaSampleRate = .nan }; if mode == 5 { f.player.ownMediaSampleRate = 192_001 }
            XCTAssertThrowsError(try f.prepare()); XCTAssertEqual(f.player.played, 0); XCTAssertGreaterThan(f.player.stopped, 0)
        }
    }
    func testCurrentAuthorityAndPlaybackEnvironmentRecheckedAtPlay() throws {
        for mode in 0..<2 { let f = OwnerAudioDeviceFixture(); try f.prepare(); if mode == 0 { f.current = false } else { f.permits = false }
            XCTAssertThrowsError(try f.device.play()); XCTAssertEqual(f.player.played, 0); XCTAssertNil(f.player.delegate)
        }
    }
    func testReentrantPrepareCannotPlayRetiredPlayer() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); f.player.onPrepare = { f.device.stop() }
        XCTAssertThrowsError(try f.device.play()); XCTAssertEqual(f.player.played, 0)
    }
    func testBackgroundStopsSynchronouslyAndDoesNotResume() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); try f.device.play()
        f.notes.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(f.events, [.interrupted]); XCTAssertEqual(f.player.stopped, 1)
        f.notes.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue, AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        XCTAssertEqual(f.player.played, 1)
    }
    func testInterruptionRouteAndResetStopOnlyCurrentInstance() throws {
        let cases: [(Notification.Name, [AnyHashable: Any]?)] = [
            (AVAudioSession.interruptionNotification, [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]),
            (AVAudioSession.routeChangeNotification, [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]),
            (AVAudioSession.routeChangeNotification, [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue]),
            (AVAudioSession.mediaServicesWereResetNotification, nil)]
        for (name, info) in cases { let f = OwnerAudioDeviceFixture(); try f.prepare(); try f.device.play(); f.notes.post(name: name, object: nil, userInfo: info)
            XCTAssertEqual(f.events, [.interrupted]); XCTAssertEqual(f.player.stopped, 1)
        }
    }
    func testOldCompletionCannotStopNewPlayer() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); let old = f.player; f.player = OwnerAudioMemoryPlayer(); try f.prepare(); try f.device.play()
        f.device.receiveCompletion(from: old, succeeded: false); XCTAssertTrue(f.events.isEmpty); XCTAssertEqual(f.player.stopped, 0)
        f.device.receiveCompletion(from: f.player, succeeded: true); XCTAssertEqual(f.events, [.ended]); XCTAssertEqual(f.player.stopped, 1)
    }
    func testExplicitFailureAndInvalidSeekCannotEscapeBounds() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare()
        for value in [Double.nan, .infinity, -1, 31] { XCTAssertThrowsError(try f.device.seek(value)) }
        XCTAssertEqual(f.player.currentTime, 0); f.player.playOK = false; XCTAssertThrowsError(try f.device.play()); XCTAssertNil(f.player.delegate)
    }
    func testOldReentrantPrepareCannotStopReplacementPlayer() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); let old = f.player
        old.onPrepare = { f.player = OwnerAudioMemoryPlayer(); try? f.prepare() }
        XCTAssertThrowsError(try f.device.play()); XCTAssertEqual(old.played, 0); XCTAssertEqual(f.player.stopped, 0)
        try f.device.play(); XCTAssertEqual(f.player.played, 1); f.device.stop()
    }
    func testOldReentrantPlayFailureCannotStopReplacementPlayer() throws {
        let f = OwnerAudioDeviceFixture(); try f.prepare(); let old = f.player; old.playOK = false
        old.onPlay = { f.player = OwnerAudioMemoryPlayer(); try? f.prepare() }
        XCTAssertThrowsError(try f.device.play()); XCTAssertEqual(f.player.stopped, 0)
        try f.device.play(); XCTAssertEqual(f.player.played, 1); f.device.stop()
    }

}

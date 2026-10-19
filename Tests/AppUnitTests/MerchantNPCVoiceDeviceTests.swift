import XCTest
import AVFoundation
@testable import Questify

/// Exercises only default-off guards. Never requests permission or touches an audio session.
@MainActor final class MerchantNPCVoiceDeviceTests: XCTestCase {
    func testDefaultProviderCannotRequestMicrophone() async throws {
        let provider = MerchantNPCAVVoiceDevice()
        let limits = try MerchantNPCVoiceConfiguration(sampleRate: 16000, channels: 1, bitRate: 32000, minDuration: 1, maxDuration: 10, maxBytes: 1000, approvedHosts: ["synthetic.invalid"])
        do { try await provider.start(configuration: limits, interrupted: { XCTFail() }); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }
    }
    func testDefaultProviderCannotPlay() {
        let provider = MerchantNPCAVVoiceDevice()
        XCTAssertThrowsError(try provider.play(.init(bytes: Data(), duration: 0))) { XCTAssertEqual($0 as? MerchantNPCFailure, .disabled) }
        provider.cancel()
    }
}

/// Lifecycle hygiene of the merchant voice device without starting a recorder or session.
@MainActor final class MerchantNPCVoiceDeviceLifecycleTests: XCTestCase {
    func testIdleDeviceHoldsNoObserversAndIgnoresLifecycleNotifications() {
        let center = NotificationCenter()
        let provider = MerchantNPCAVVoiceDevice(notifications: center)
        XCTAssertEqual(provider.lifecycleRegistrations, 0)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        provider.cancel(); provider.cancel()
        XCTAssertEqual(provider.lifecycleRegistrations, 0)
    }
    func testOrphanedTakesAreSweptAndLiveOrUnrelatedFilesKept() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("merchant-voice-sweep-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func write(_ url: URL, age: TimeInterval) throws {
            try Data([1]).write(to: url)
            try files.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        let orphan = MerchantNPCVoiceTemporaryFiles.make(in: directory)
        let live = MerchantNPCVoiceTemporaryFiles.make(in: directory)
        let unrelated = directory.appendingPathComponent("shop-npc-synthetic.m4a")
        let otherType = directory.appendingPathComponent("merchant-voice-synthetic.json")
        try write(orphan, age: 3600); try write(live, age: 5); try write(unrelated, age: 3600); try write(otherType, age: 3600)
        MerchantNPCVoiceTemporaryFiles.sweep(in: directory, now: now)
        XCTAssertFalse(files.fileExists(atPath: orphan.path))
        XCTAssertTrue(files.fileExists(atPath: live.path))
        XCTAssertTrue(files.fileExists(atPath: unrelated.path))
        XCTAssertTrue(files.fileExists(atPath: otherType.path))
    }
}

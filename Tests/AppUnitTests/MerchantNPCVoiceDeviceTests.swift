import XCTest
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

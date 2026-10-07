import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryFixtureCounterTests: XCTestCase {
    private struct Counts: Decodable {
        let storyImageUploadCount: Int
        let storyAudioUploadCount: Int
    }
    private func decoded(image: ProjectStoryImageSynthetic?, audio: ProjectStoryAudioSynthetic?) throws -> Counts {
        let bytes = try JSONSerialization.data(withJSONObject: ProjectStoryMediaFixtureCounters.snapshot(image: image, audio: audio))
        return try JSONDecoder().decode(Counts.self, from: bytes)
    }
    func testAbsentSourcesSupplyBothRequiredZeroCounters() throws {
        let counts = try decoded(image: nil, audio: nil)
        XCTAssertEqual(counts.storyImageUploadCount, 0)
        XCTAssertEqual(counts.storyAudioUploadCount, 0)
    }
    func testImageOnlyUsesActualUploadCounterAndKeepsAudioExactlyZero() async throws {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "fixture-counter-test")
        let source = try ProjectStoryImageSynthetic(session: session, currentSession: { session })
        XCTAssertEqual(try decoded(image: source, audio: nil).storyImageUploadCount, 0)
        _ = try await source.upload(source.picked, attemptID: UUID(), session: session)
        let counts = try decoded(image: source, audio: nil)
        XCTAssertEqual(counts.storyImageUploadCount, source.uploadCount)
        XCTAssertEqual(counts.storyImageUploadCount, 1)
        XCTAssertEqual(counts.storyAudioUploadCount, 0)
        XCTAssertEqual(source.wire.requests.count, 1)
    }
    func testAudioOnlyTracksTwoActualUploadsAndKeepsImageExactlyZero() async throws {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "fixture-counter-test")
        let source = try ProjectStoryAudioSynthetic(session: session, currentSession: { session })
        for expected in 1...2 {
            _ = try await source.upload(source.picked, attemptID: UUID(), session: session)
            let counts = try decoded(image: nil, audio: source)
            XCTAssertEqual(counts.storyAudioUploadCount, source.uploadCount)
            XCTAssertEqual(counts.storyAudioUploadCount, expected)
            XCTAssertEqual(counts.storyImageUploadCount, 0)
            XCTAssertEqual(source.wire.requests.count, expected)
        }
    }
}
#endif

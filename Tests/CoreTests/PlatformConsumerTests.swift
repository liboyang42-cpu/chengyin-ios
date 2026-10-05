import XCTest
@testable import QuestifyCore

@MainActor final class PlatformConsumerTests: XCTestCase {
    private let policy = PlatformMediaPolicy(approvedOrigins: ["https://media.example.test"])
    private func source(_ path: String = "one.mp3", scope: UUID = UUID()) -> PlatformMediaSource {
        PlatformMediaSource(url: URL(string: "https://media.example.test/" + path)!, scope: scope)
    }
    func testDefaultOffAndExactOrigin() {
        let fake = SyntheticPlatformAudioDriver(), model = PlatformAudioPlayback(driver: SyntheticPlatformAudioDriver())
        model.select(source()); model.approveSelectedMedia(); model.toggle(); XCTAssertEqual(model.state, .gated)
        let gated = PlatformAudioPlayback(driver: fake, policy: policy)
        gated.select(source()); gated.approveSelectedMedia(); gated.toggle(); XCTAssertEqual(fake.starts, 0)
        for raw in ["http://media.example.test/a", "https://media.example.test.evil/a", "https://user:secret@media.example.test/a", "https://media.example.test:8443/a"] { XCTAssertFalse(policy.allows(URL(string: raw)!)) }
        XCTAssertTrue(policy.allows(URL(string: "https://media.example.test:443/a")!))
    }
    func testPlaybackErrorCompletionAndRepeat() {
        let fake = SyntheticPlatformAudioDriver(), value = source()
        let model = PlatformAudioPlayback(driver: fake, policy: policy, enabled: true)
        model.select(value); model.toggle(); XCTAssertEqual(fake.starts, 0)
        model.approveSelectedMedia(); model.toggle(); XCTAssertEqual(model.state, .loading)
        model.toggle(); XCTAssertEqual(fake.starts, 1)
        fake.event?(.playing); XCTAssertEqual(model.state, .playing)
        model.toggle(); XCTAssertEqual(model.state, .paused)
        model.toggle(); XCTAssertEqual(model.state, .playing)
        fake.event?(.ended); XCTAssertEqual(model.state, .ended)
        model.toggle(); XCTAssertEqual(fake.starts, 2)
        fake.event?(.failed); XCTAssertEqual(model.state, .failed)
        model.toggle(); XCTAssertEqual(fake.starts, 3)
    }
    func testScopeSourceBackgroundAndDisposeFenceLateCallbacks() {
        let fake = SyntheticPlatformAudioDriver(), model = PlatformAudioPlayback(driver: SyntheticPlatformAudioDriver())
        model.dispose(); model.select(source()); XCTAssertEqual(model.state, .disposed)
        let playback = PlatformAudioPlayback(driver: fake, policy: policy, enabled: true)
        playback.select(source()); playback.approveSelectedMedia(); playback.toggle()
        let old = fake.event
        playback.select(source("two.mp3")); old?(.playing); XCTAssertEqual(playback.state, .idle)
        playback.toggle(); XCTAssertEqual(fake.starts, 1)
        playback.approveSelectedMedia(); playback.toggle(); let pending = fake.event
        playback.suspend(); pending?(.failed); XCTAssertEqual(playback.state, .idle)
        playback.toggle(); XCTAssertEqual(fake.starts, 2)
        playback.approveSelectedMedia(); playback.toggle(); fake.event?(.interrupted); XCTAssertEqual(playback.state, .idle)
        playback.dispose(); pending?(.playing); XCTAssertEqual(playback.state, .disposed)
    }
    func testSelectedDestinationMissingCoordinatesAndFallback() async {
        let fake = SyntheticPlatformMapAdapter()
        let model = PlatformExternalMaps(opener: fake, copier: fake, enabled: true)
        let missing = PlatformMapDestination(name: "Missing", latitude: 0, longitude: 120)
        model.select(missing); await model.openReviewedDestination(missing)
        XCTAssertEqual(model.state, .noCoordinates); XCTAssertTrue(fake.opened.isEmpty)
        let value = PlatformMapDestination(name: "Place", address: "Address", latitude: 31, longitude: 121)
        await model.openReviewedDestination(value); XCTAssertTrue(fake.opened.isEmpty)
        model.select(value); await model.openReviewedDestination(value)
        XCTAssertEqual(model.state, .launchFailed); XCTAssertTrue(fake.copied.isEmpty)
        model.copySelectedAddress(); XCTAssertEqual(model.state, .copied); XCTAssertEqual(fake.copied, ["Place Address"])
        fake.failCopy = true; model.copySelectedAddress(); XCTAssertEqual(model.state, .copyFailed)
        fake.result = true; await model.openReviewedDestination(value); XCTAssertEqual(model.state, .opened)
        model.invalidate(); XCTAssertNil(model.selected)
    }
    func testMapDefaultOffAndBadCoordinates() async {
        let fake = SyntheticPlatformMapAdapter(), value = PlatformMapDestination(name: "Place", latitude: 31, longitude: 121)
        let model = PlatformExternalMaps(opener: fake, copier: fake)
        model.select(value); await model.openReviewedDestination(value); model.copySelectedAddress()
        XCTAssertEqual(model.state, .gated); XCTAssertTrue(fake.opened.isEmpty); XCTAssertTrue(fake.copied.isEmpty)
        for point in [(Double.nan, 121.0), (31, Double.infinity), (91, 121), (31, 181), (31, 0)] {
            XCTAssertFalse(PlatformMapDestination(name: "Invalid", latitude: point.0, longitude: point.1).hasCoordinates)
        }
    }
}

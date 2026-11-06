import XCTest
@testable import QuestifyCore

final class PlatformChapterAudioTests: XCTestCase {
    private func snapshot(locked: Bool = false, playable: Bool = true, registered: Bool = true, hidden: Bool = false, chapterID: Int = 7) throws -> (PlaySnapshot, [Int: PlayNodeExtras]) {
        let raw = """
        {"topicId":10,"playable":\(playable),"registered":\(registered),"nodes":[{"nodeId":1,"chapterId":\(chapterID),"locked":\(locked),"routeNodeState":"\(hidden ? "HIDDEN" : "PLAYABLE")","audioUrl":"https://media.example.test/guide.mp3"}],"chapters":[{"chapterId":7,"name":"Chapter","audioUrl":"https://media.example.test/narration.mp3"}]}
        """
        let document = try JSONDecoder().decode(PlayExperienceDocument.self, from: Data(raw.utf8))
        return (try PlaySnapshot(scope: .topic(10), result: document.base), document.extras)
    }
    func testSameReadDecodesDistinctNarrationAndGuide() throws {
        let (snapshot, extras) = try snapshot()
        let selection = PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 1, extras: extras, currentRead: true)
        XCTAssertEqual(selection?.chapterID, 7)
        XCTAssertEqual(selection?.narrationURL, "https://media.example.test/narration.mp3")
        XCTAssertEqual(selection?.guideURL, "https://media.example.test/guide.mp3")
    }
    func testLockVisibilitySessionAndIdentityMustAllMatch() throws {
        let variants = [try snapshot(locked: true), try snapshot(playable: false), try snapshot(registered: false), try snapshot(hidden: true), try snapshot(chapterID: 8)]
        for (snapshot, extras) in variants {
            XCTAssertNil(PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 1, extras: extras, currentRead: true))
        }
        let (snapshot, extras) = try snapshot()
        XCTAssertNil(PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 1, extras: extras, currentRead: false))
        XCTAssertNil(PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 999, extras: extras, currentRead: true))
    }
    func testOldChapterWithoutAudioStillDecodes() throws {
        let chapter = try JSONDecoder().decode(PlayChapter.self, from: Data("{\"chapterId\":7,\"name\":\"Old\"}".utf8))
        XCTAssertNil(chapter.audioURL)
    }
    func testLifecyclePolicyStopsOnPreemptionAndNeverResumes() {
        let stops: [PlatformAudioLifecycleSignal] = [.interruptionBegan, .routeOldDeviceUnavailable, .routeOther,
                                                     .mediaServicesReset, .enteredBackground, .unknown]
        for signal in stops {
            XCTAssertEqual(PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: true), .stop, "\(signal)")
            XCTAssertEqual(PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: false), .stop, "\(signal)")
        }
        for resume in [true, false] {
            XCTAssertEqual(PlatformAudioLifecyclePolicy.action(for: .interruptionEnded(shouldResume: resume), ownsConfiguration: true), .ignore)
            XCTAssertEqual(PlatformAudioLifecyclePolicy.action(for: .interruptionEnded(shouldResume: resume), ownsConfiguration: false), .ignore)
        }
        for signal in [PlatformAudioLifecycleSignal.routeCategoryChange, .routeNewDeviceAvailable] {
            XCTAssertEqual(PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: true), .ignore)
            XCTAssertEqual(PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: false), .stop)
        }
    }
    @MainActor private func playing(_ driver: SyntheticPlatformAudioDriver, path: String = "narration.mp3") -> PlatformAudioPlayback {
        let playback = PlatformAudioPlayback(driver: driver, policy: .init(approvedOrigins: ["https://media.example.test"]), enabled: true)
        playback.select(.init(url: URL(string: "https://media.example.test/" + path)!, scope: UUID()))
        playback.approveSelectedMedia(); playback.toggle(); driver.event?(.playing)
        return playback
    }
    @MainActor func testUserPauseThenInterruptionReleasesAndOnlyExplicitTapRestarts() {
        let driver = SyntheticPlatformAudioDriver(), playback = playing(driver)
        playback.toggle(); XCTAssertEqual(playback.state, .paused)
        driver.event?(.interrupted)
        XCTAssertEqual(playback.state, .idle); XCTAssertNil(driver.event); XCTAssertEqual(driver.starts, 1)
        playback.toggle(); XCTAssertEqual(playback.state, .loading); XCTAssertEqual(driver.starts, 2)
        driver.event?(.playing); XCTAssertEqual(playback.state, .playing)
        playback.dispose()
    }
    @MainActor func testOldRunCallbackCannotDriveReplacementOrDisposedPlayback() throws {
        let driver = SyntheticPlatformAudioDriver(), playback = playing(driver)
        let old = try XCTUnwrap(driver.event)
        playback.select(.init(url: URL(string: "https://media.example.test/next.mp3")!, scope: UUID()))
        playback.approveSelectedMedia(); playback.toggle()
        old(.playing); old(.interrupted); old(.ended)
        XCTAssertEqual(playback.state, .loading)
        driver.event?(.playing); XCTAssertEqual(playback.state, .playing)
        let current = try XCTUnwrap(driver.event)
        playback.suspend(); current(.playing)
        XCTAssertEqual(playback.state, .idle)
        playback.toggle(); XCTAssertEqual(driver.starts, 2) // Suspension (page exit/background/account) clears consent.
        playback.dispose(); current(.playing); XCTAssertEqual(playback.state, .disposed)
    }
}

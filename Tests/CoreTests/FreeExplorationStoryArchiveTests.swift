import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// FE-STORY offline archive (6.2 / 7.3), expired history (7.4) and teammate visits (5.5).
/// Synthetic places only.
@MainActor final class FreeExplorationStoryArchiveTests: XCTestCase {
    private let locked = #"{"topicId":71,"topicName":"Synthetic story walk","mode":2,"registered":true,"playable":true,"total":2,"doneCount":0,"storyUnlocked":1,"storyTotal":2,"chapters":[{"chapterId":81,"name":"Synthetic chapter one","description":"Synthetic locked chapter text","chapterLocked":true},{"chapterId":82,"name":"Synthetic chapter two","description":"Synthetic shared chapter text","chapterLocked":false},{"chapterId":83,"name":"Synthetic unknown chapter"}],"nodes":[{"nodeId":701,"name":"示例站点 A","chapterId":81,"done":false,"arrived":false,"visitCheck":"GPS","storyLocked":true,"description":"Synthetic stale locked description","storyText":"Synthetic stale locked story","fragmentText":"Synthetic stale fragment"},{"nodeId":702,"name":"示例站点 B","chapterId":82,"done":false,"arrived":true,"visited":true,"visitedByTeam":true,"visitTime":null,"storyLocked":false,"description":"Synthetic team unlocked text","fragmentText":"Synthetic fragment B","cardHookLong":"Synthetic long hook B"}]}"#
    private let history = #"{"readOnly":true,"mode":2,"storyUnlocked":1,"storyTotal":2,"chapters":[{"chapterId":82,"name":"Synthetic chapter two","sortId":2,"description":"Synthetic shared chapter text","blocks":[{"type":"text","content":"Synthetic block"},{"type":"image","url":"https://example.test/a.jpg"}]}],"nodes":[{"nodeId":702,"name":"示例站点 B","chapterId":82,"fragmentText":"Synthetic kept fragment","visitTime":1763344800000,"visitedByTeam":false}]}"#

    private func session(account: Int = 7) throws -> PlayExperienceSession { try .init(accountID: account, epoch: 1, namespace: "synthetic", token: "synthetic") }
    private func snapshot(_ json: String, scope: PlaySessionScope = .activity(41)) throws -> PlaySnapshot {
        try PlaySnapshot(scope: scope, result: JSONDecoder().decode(PlayNodesResult.self, from: Data(json.utf8)))
    }
    private func archive(_ json: String, account: Int = 7) throws -> FreeExplorationStoryArchive {
        try XCTUnwrap(FreeExplorationStoryArchive(snapshot: snapshot(json), chapterStories: [:], owner: .init(session: session(account: account))))
    }
    private func encoded(_ archive: FreeExplorationStoryArchive) throws -> String {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .xml
        return String(decoding: try encoder.encode(archive), as: UTF8.self)
    }

    // MARK: Contract

    func testTeammateVisitDecodes() throws {
        let nodes = try snapshot(locked).result.nodes
        XCTAssertNil(nodes[0].visitedByTeam); XCTAssertEqual(nodes[1].visitedByTeam, true)
        XCTAssertEqual(nodes[1].visited, true); XCTAssertNil(nodes[1].visitTime)
        XCTAssertEqual(nodes[1].fragmentText, "Synthetic fragment B"); XCTAssertEqual(nodes[1].cardHookLong, "Synthetic long hook B")
        let malformed = try snapshot(#"{"mode":2,"registered":true,"playable":true,"nodes":[{"nodeId":701,"visitedByTeam":"maybe","fragmentText":7}]}"#).result.nodes[0]
        XCTAssertNil(malformed.visitedByTeam); XCTAssertNil(malformed.fragmentText)
    }

    func testHistoryDecodesOnlyReadOnlyFreeExploration() throws {
        let document = try FreeExplorationHistoryDocument(raw: PlayExperienceSyntheticFixtures.wire(history))
        XCTAssertEqual(document.chapters.map(\.chapterID), [82]); XCTAssertEqual(document.nodes.map(\.nodeID), [702])
        XCTAssertEqual(document.nodes[0].visitTime, .epochMilliseconds(1_763_344_800_000)); XCTAssertEqual(document.storyTotal, 2)
        for bad in [history.replacingOccurrences(of: #""readOnly":true"#, with: #""readOnly":false"#),
                    history.replacingOccurrences(of: #""mode":2"#, with: #""mode":1"#),
                    history.replacingOccurrences(of: #""nodeId":702"#, with: #""nodeId":0"#),
                    #"{"readOnly":true,"mode":2,"chapters":[],"nodes":[{"nodeId":1},{"nodeId":1}]}"#] {
            XCTAssertThrowsError(try FreeExplorationHistoryDocument(raw: PlayExperienceSyntheticFixtures.wire(bad)), bad)
        }
    }

    // MARK: Archive

    func testArchiveKeepsOnlyVisitedTextAndNamesLockedPlaces() throws {
        let value = try archive(locked)
        XCTAssertEqual(value.places.map(\.id), [702]); XCTAssertTrue(value.places[0].visitedByTeam); XCTAssertNil(value.places[0].visitTime)
        XCTAssertEqual(value.places[0].paragraphs, ["Synthetic team unlocked text", "Synthetic long hook B", "Synthetic fragment B"])
        // A locked chapter, and one with unknown lock state and no visited place, stay out.
        XCTAssertEqual(value.chapters.map(\.id), [82]); XCTAssertEqual(value.chapters[0].paragraphs, ["Synthetic shared chapter text"])
        XCTAssertEqual(value.lockedPlaces, [.init(id: 701, name: "示例站点 A")])
        XCTAssertEqual(value.storyUnlocked, 1); XCTAssertEqual(value.storyTotal, 2); XCTAssertEqual(value.topicID, 71)
        let bytes = try encoded(value)
        for secret in ["Synthetic stale locked description", "Synthetic stale locked story", "Synthetic stale fragment", "Synthetic locked chapter text"] {
            XCTAssertFalse(bytes.contains(secret), secret)
        }
        XCTAssertNil(FreeExplorationStoryArchive(snapshot: try snapshot(#"{"mode":1,"registered":true,"playable":true,"nodes":[{"nodeId":701,"storyLocked":false,"storyText":"City"}]}"#), chapterStories: [:], owner: .init(session: session())))
    }

    func testArchiveRoundTripsAndMergesWithoutLosingEarlierVisits() throws {
        let first = try archive(locked)
        let decoded = try PropertyListDecoder().decode(FreeExplorationStoryArchive.self, from: PropertyListEncoder().encode(first))
        XCTAssertEqual(decoded, first)
        let later = try archive(locked.replacingOccurrences(of: #""storyLocked":true"#, with: #""storyLocked":false,"visited":true"#)
            .replacingOccurrences(of: #""visitTime":null,"#, with: ""))
        XCTAssertEqual(Set(later.places.map(\.id)), [701, 702])
        // A later read that no longer lists 701 (delisted) keeps the earlier unlocked copy.
        let delisted = try archive(#"{"topicId":71,"mode":2,"registered":true,"playable":true,"nodes":[{"nodeId":702,"chapterId":82,"visited":true,"storyLocked":false,"description":"Synthetic newer B"}]}"#)
        let merged = later.merging(delisted)
        XCTAssertEqual(Set(merged.places.map(\.id)), [701, 702])
        XCTAssertEqual(merged.places.first { $0.id == 702 }?.description, "Synthetic newer B")
        XCTAssertTrue(merged.lockedPlaces.isEmpty)
        // Another account never inherits rows.
        let foreign = try archive(locked, account: 8)
        XCTAssertEqual(later.merging(foreign), foreign)
    }

    func testHistoryArchiveListsVisitedChaptersAndKnownLockedPlaces() throws {
        let document = try FreeExplorationHistoryDocument(raw: PlayExperienceSyntheticFixtures.wire(history))
        let value = FreeExplorationStoryArchive(history: document, owner: .init(session: try session()), topicID: 71, topicName: nil,
                                                knownPlaces: [.init(id: 701, name: "示例站点 A"), .init(id: 702, name: "示例站点 B")])
        XCTAssertEqual(value.chapters.map(\.id), [82]); XCTAssertEqual(value.chapters[0].paragraphs, ["Synthetic shared chapter text", "Synthetic block"])
        XCTAssertEqual(value.places.map(\.id), [702]); XCTAssertEqual(value.lockedPlaces.map(\.id), [701])
        XCTAssertEqual(value.places[0].paragraphs, ["Synthetic kept fragment"])
    }

    func testDurableSlotIsAccountBoundAndFailsClosed() async throws {
        let a = PlayDurableRecoveryTests.Anchors(), b = PlayDurableRecoveryTests.Blobs(), owner = try session()
        let key = PlayRunStorageKey.make(session: owner, scope: .activity(41))
        let durable = try PlayDurableRecovery(owner: .init(session: owner), key: key, anchors: a, ciphertexts: b)
        let empty = try await durable.readStoryArchive(key: key); XCTAssertNil(empty)
        let value = try archive(locked)
        try await durable.writeStoryArchive(value, key: key)
        let read = try await durable.readStoryArchive(key: key); XCTAssertEqual(read, value)
        // The completion journal is a separate slot and stays empty.
        let pending = try await durable.read(key); XCTAssertNil(pending)
        for blob in await b.snapshots() { XCTAssertNil(blob.range(of: Data("Synthetic team unlocked text".utf8))) }
        do { try await durable.writeStoryArchive(try archive(locked, account: 8), key: key); XCTFail("foreign owner") }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        do { _ = try await durable.readStoryArchive(key: key + "x"); XCTFail("foreign key") }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        let other = try PlayDurableRecovery(owner: .init(session: try session(account: 8)), key: key, anchors: a, ciphertexts: b)
        do { _ = try await other.readStoryArchive(key: key); XCTFail("foreign account") }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
    }

    // MARK: Coordinator

    private func coordinator(_ wire: PlayRecoveryRecordingTransport, scope: PlaySessionScope = .activity(41), store: FreeExplorationMemoryStoryArchive) throws -> PlayExperienceCoordinator {
        let owner = try session()
        return .init(scope: scope, service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: [.reads, .classicCompletion]),
                     recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner }, storyArchive: store)
    }
    private func writes(_ wire: PlayRecoveryRecordingTransport) -> [URLRequest] { wire.requests.filter { $0.httpMethod == "POST" } }

    func testOfflineReadShowsSavedUnlockedChaptersAndNeverWrites() async throws {
        let wire = PlayRecoveryRecordingTransport(), store = FreeExplorationMemoryStoryArchive()
        wire.queues["/api/play/nodes"] = [.reply(PlayExperienceSyntheticFixtures.envelope(locked), 200)]
        wire.responses["/api/play/nodes"] = .offline
        let runtime = try coordinator(wire, store: store)
        await runtime.load()
        XCTAssertNotNil(runtime.snapshot); XCTAssertNil(runtime.storyArchive)
        await runtime.load()
        XCTAssertNil(runtime.snapshot); XCTAssertEqual(runtime.phase, .failed)
        XCTAssertEqual(runtime.storyArchiveSource, .offline); XCTAssertEqual(runtime.storyArchive?.places.map(\.id), [702])
        XCTAssertEqual(runtime.storyArchive?.lockedPlaces.map(\.id), [701])
        XCTAssertFalse(runtime.canSubmitArrival); XCTAssertTrue(writes(wire).isEmpty)
        // A server failure is not offline: no device copy is shown for it.
        wire.responses["/api/play/nodes"] = .failure(.malformed)
        await runtime.load()
        XCTAssertNil(runtime.storyArchive); XCTAssertNil(runtime.storyArchiveSource)
        // Another account never reads this copy.
        runtime.invalidate(); XCTAssertNil(runtime.storyArchive)
    }

    func testExpiredReadUsesHistoryWithoutRouteSessionAndShowsOnlyVisited() async throws {
        let wire = PlayRecoveryRecordingTransport(), store = FreeExplorationMemoryStoryArchive()
        wire.responses["/api/play/nodes"] = .reply(Data(#"{"code":402,"msg":"Synthetic expired"}"#.utf8), 200)
        wire.responses["/api/play/history"] = .reply(PlayExperienceSyntheticFixtures.envelope(history), 200)
        let runtime = try coordinator(wire, scope: .topic(71), store: store)
        await runtime.load()
        XCTAssertEqual(runtime.storyArchiveSource, .expired)
        XCTAssertEqual(runtime.storyArchive?.places.map(\.id), [702]); XCTAssertEqual(runtime.storyArchive?.chapters.map(\.id), [82])
        let request = try XCTUnwrap(wire.requests.first { $0.url?.path == "/api/play/history" })
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }), ["activityId": "0", "topicId": "71"])
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertTrue(writes(wire).isEmpty)
    }

    func testNotPlayableSnapshotReadsHistoryForItsTopic() async throws {
        let wire = PlayRecoveryRecordingTransport(), store = FreeExplorationMemoryStoryArchive()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(locked.replacingOccurrences(of: #""playable":true"#, with: #""playable":false"#)), 200)
        wire.responses["/api/play/history"] = .reply(PlayExperienceSyntheticFixtures.envelope(history), 200)
        let runtime = try coordinator(wire, store: store)
        await runtime.load()
        XCTAssertEqual(runtime.storyArchiveSource, .expired); XCTAssertEqual(runtime.storyArchive?.lockedPlaces.map(\.id), [701])
        let request = try XCTUnwrap(wire.requests.first { $0.url?.path == "/api/play/history" })
        XCTAssertTrue(request.url?.query?.contains("activityId=41") == true); XCTAssertTrue(request.url?.query?.contains("topicId=71") == true)
        XCTAssertFalse(request.url?.query?.contains("routeSessionId") == true)
        XCTAssertNil(PlayArrivalService(runtime: runtime, location: nil).offer(for: 701))
        // A city route never reads FE history.
        let city = PlayRecoveryRecordingTransport()
        city.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"mode":1,"registered":true,"playable":false,"nodes":[{"nodeId":701,"done":false}]}"#), 200)
        let cityRuntime = try coordinator(city, store: FreeExplorationMemoryStoryArchive()); await cityRuntime.load()
        XCTAssertNil(cityRuntime.storyArchive); XCTAssertFalse(city.requests.contains { $0.url?.path == "/api/play/history" })
    }

    func testOfflineClassificationIsTransportOnly() {
        XCTAssertTrue(PlayExperienceCoordinator.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(PlayExperienceCoordinator.isOffline(URLError(.timedOut)))
        XCTAssertFalse(PlayExperienceCoordinator.isOffline(URLError(.badServerResponse)))
        XCTAssertFalse(PlayExperienceCoordinator.isOffline(PlayExperienceError.unknownResult))
    }
}

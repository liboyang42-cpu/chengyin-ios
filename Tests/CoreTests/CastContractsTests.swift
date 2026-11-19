import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cast contract v1 (hengyin docs/design/cast-contract-1119.md). Fictional sample text only.
final class CastContractsTests: XCTestCase {
    static let config = ##"{"enabled":true,"playerName":true,"playerIdentity":true,"identities":[{"key":"i_a","title":"信使","sub":"替灯塔送一封信"},{"key":"i_a","title":"重复"}],"cast":[{"id":"c_a","name":"阿岚","identity":"守塔人，雾夜里点灯的人","color":"#3d8bfd","voice":{"mode":"preset","preset":"warm_female"},"clues":[{"text":"她总在午夜换灯芯","chapterId":null},{"text":"塔下埋着一只铁盒","chapterId":9}],"lockedCount":2,"endingLines":{"high":"灯会一直为你亮着。","low":"她没有回头。"}},{"id":"c_b","name":"渡口","color":"#123456","voice":{"mode":"none"}},{"id":"c_a","name":"重复编号"},{"id":"c_c","name":"名字太长了超过八个字"}]}"##

    func testAbsentNullDisabledOrMalformedConfigMeansFeatureOff() throws {
        XCTAssertNil(CastConfig(raw: .null))
        XCTAssertNil(CastConfig(raw: try wire(#"{"enabled":false,"cast":[{"id":"c_a","name":"阿岚"}]}"#)))
        XCTAssertNil(CastConfig(raw: .string("not json")))
        XCTAssertNil(CastConfig(raw: .array([])))
    }
    func testConfigDecodesLimitsPaletteAndJSONTextColumn() throws {
        let config = try XCTUnwrap(CastConfig(raw: wire(Self.config)))
        XCTAssertEqual(config.cast.map(\.id), ["c_a", "c_b"]) // duplicate id and over-long name dropped
        XCTAssertEqual(config.identities.map(\.key), ["i_a"])
        XCTAssertEqual(config.cast[0].color, "#3D8BFD")
        XCTAssertEqual(config.cast[1].color, CastMember.neutralColor)
        XCTAssertTrue(config.cast[0].hasPresetVoice); XCTAssertFalse(config.cast[1].hasPresetVoice)
        XCTAssertEqual(config.cast[0].identityLead, "守塔人")
        XCTAssertEqual(CastConfig(raw: .string(Self.config)), config)
        let many = "[" + (0..<15).map { #"{"id":"c_\#($0)","name":"人\#($0)"}"# }.joined(separator: ",") + "]"
        XCTAssertEqual(CastConfig(raw: try wire(#"{"enabled":true,"cast":\#(many)}"#))?.cast.count, 12)
    }
    func testStartStepOnlyWhenAskingAndNoProfile() throws {
        let config = try XCTUnwrap(CastConfig(raw: wire(Self.config)))
        XCTAssertTrue(config.needsStartStep(profile: nil))
        XCTAssertFalse(config.needsStartStep(profile: CastPlayerProfile(name: nil, identityKey: nil)))
        let silent = try XCTUnwrap(CastConfig(raw: wire(#"{"enabled":true,"playerName":false,"playerIdentity":true,"identities":[],"cast":[]}"#)))
        XCTAssertFalse(silent.asksPlayer); XCTAssertFalse(silent.needsStartStep(profile: nil))
    }
    func testProfileIsFoundInRunStateAndTrimmed() throws {
        let profile = CastPlayerProfile.find(in: try wire(#"{"routeState":{"playerProfile":{"name":"  小舟  ","identityKey":"i_a"}}}"#))
        XCTAssertEqual(profile, CastPlayerProfile(name: "小舟", identityKey: "i_a"))
        XCTAssertNil(CastPlayerProfile.find(in: try wire(#"{"routeState":{}}"#)))
        XCTAssertNil(CastPlayerProfile(name: "   ", identityKey: "").name)
    }
    func testLineBlocksResolveSpeakersAndFillPlayerVariables() throws {
        let config = try XCTUnwrap(CastConfig(raw: wire(Self.config)))
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"blocks":[{"key":"b1","type":"line","speaker":"c_a","content":"{玩家}，你来了。","audioUrl":"https://voice.test/a.mp3"},{"key":"b2","type":"line","speaker":"player","content":"我是{身份}。"},{"key":"b3","type":"line","speaker":"c_gone","content":"被删掉的角色"},{"type":"line","speaker":"c_a","content":"   "}]}"#))
        let named = ChapterStoryProjection.segments(chapter: chapter, snapshot: try snapshot(), variables: [:],
            cast: CastStoryContext(config: config, profile: CastPlayerProfile(name: "小舟", identityKey: "i_a")))
        XCTAssertEqual(named.map(\.content), [
            .line(.init(speaker: .cast("c_a"), text: "小舟，你来了。", audioURL: "https://voice.test/a.mp3", blockKey: "b1")),
            .line(.init(speaker: .player, text: "我是信使。", blockKey: "b2")),
            .line(.init(speaker: nil, text: "被删掉的角色", blockKey: "b3"))])
        let anonymous = ChapterStoryProjection.segments(chapter: chapter, snapshot: try snapshot(), variables: [:],
            cast: CastStoryContext(config: config, profile: nil))
        XCTAssertEqual(anonymous.first?.content, .line(.init(speaker: .cast("c_a"), text: "你，你来了。", audioURL: "https://voice.test/a.mp3", blockKey: "b1")))
        // Cast off: a line is still one plain paragraph, never a crash and never a name.
        let off = ChapterStoryProjection.segments(chapter: chapter, snapshot: try snapshot(), variables: [:])
        XCTAssertEqual(off[0].content, .line(.init(speaker: nil, text: "{玩家}，你来了。", audioURL: "https://voice.test/a.mp3", blockKey: "b1")))
    }
    func testTextWhoMovesToTheMarginOfTheFirstParagraphOnly() throws {
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"blocks":[{"type":"text","who":"船夫","content":"雾很大。\n\n我们等一等。"},{"type":"text","who":"  ","content":"无名"}]}"#))
        let rows = ChapterStoryProjection.segments(chapter: chapter, snapshot: try snapshot(), variables: [:])
        XCTAssertEqual(rows.map(\.content), [.line(.init(speaker: .named("船夫"), text: "雾很大。")), .text("我们等一等。"), .text("无名")])
        XCTAssertFalse(rows.contains { if case .text(let text) = $0.content { return text.contains("：") }; return false })
    }
    func testTrustTicksBandsAndShapes() throws {
        XCTAssertEqual(CastTrust(raw: try wire(#"{"c_a":3,"c_b":"-1"}"#)).values, ["c_a": 3, "c_b": -1])
        XCTAssertEqual(CastTrust(raw: try wire(#"[{"castId":"c_a","trust":2},{"castId":"c_b","value":-2}]"#)).values, ["c_a": 2, "c_b": -2])
        XCTAssertEqual([-3, 0, 2, 9].map(CastTrust.filledTicks), [0, 0, 2, 5])
        XCTAssertEqual([-1, 0, 2, 3].map(CastTrust.band), [.low, .mid, .mid, .high])
        XCTAssertEqual(CastTrust.find(in: try wire(#"{"routeState":{"trust":{"c_a":1}}}"#))["c_a"], 1)
        XCTAssertEqual(CastTrust()["missing"], 0)
    }
    func testCluesUnlockByReachedChapterAndCountWithheldText() throws {
        let member = try XCTUnwrap(CastConfig(raw: wire(Self.config))?.cast.first)
        XCTAssertEqual(member.knownClues(reachedChapters: [8]).map(\.text), ["她总在午夜换灯芯"])
        XCTAssertEqual(member.remainingClueCount(reachedChapters: [8]), 3)
        XCTAssertEqual(member.knownClues(reachedChapters: [8, 9]).count, 2)
        XCTAssertEqual(member.remainingClueCount(reachedChapters: [8, 9]), 2)
    }
    func testEndingCarriesTrustOwnerAndLegacyEndingStillDecodes() throws {
        let config = try XCTUnwrap(CastConfig(raw: wire(Self.config)))
        let ending: PlayEndingDocument = try wire(#"{"opener":"夜深了","fragments":[],"trust":{"c_a":4,"c_b":0},"endingFor":"c_a","endingCount":3}"#).decoded()
        XCTAssertEqual(ending.cast.endingFor, "c_a"); XCTAssertEqual(ending.cast.endingCount, 3)
        let rows = ending.cast.rows(config)
        XCTAssertEqual(rows.map(\.member.id), ["c_a"]); XCTAssertEqual(rows.first?.line, "灯会一直为你亮着。")
        let legacy: PlayEndingDocument = try wire(#"{"opener":"","fragments":[{"step":1,"name":"终点"}]}"#).decoded()
        XCTAssertTrue(legacy.cast.trust.isEmpty); XCTAssertNil(legacy.cast.endingFor); XCTAssertTrue(legacy.hasStory)
    }
    func testBranchEchoAndRememberedNames() throws {
        let config = try XCTUnwrap(CastConfig(raw: wire(Self.config)))
        let echo = try XCTUnwrap(CastBranchEcho(branch: wire(#"{"lastChoice":{"label":"留下来陪她","trust":[{"castId":"c_a","delta":5},{"castId":"c_a","delta":1},{"castId":"c_x","delta":1},{"castId":"c_b","delta":0}]}}"#)))
        XCTAssertEqual(echo.label, "留下来陪她"); XCTAssertEqual(echo.trust.first?.delta, 2)
        XCTAssertEqual(CastTrustDelta.remembered(echo.trust, config: config).map(\.name), ["阿岚"])
        XCTAssertTrue(CastTrustDelta.remembered(echo.trust, config: nil).isEmpty)
        XCTAssertNil(CastBranchEcho(branch: try wire(#"{"currentStep":{"options":[]}}"#)))
    }
    func testRuntimeDocumentAndTopicDetailCarryCastOrNothing() throws {
        let document: PlayExperienceDocument = try wire(#"{"topicId":9,"playable":true,"nodes":[],"castConfig":\#(Self.config),"playerProfile":{"name":"小舟"},"trust":{"c_a":1}}"#).decoded()
        XCTAssertEqual(document.castConfig?.cast.count, 2); XCTAssertEqual(document.playerProfile?.name, "小舟"); XCTAssertEqual(document.trust["c_a"], 1)
        let plain: PlayExperienceDocument = try wire(#"{"topicId":9,"playable":true,"nodes":[],"castConfig":null}"#).decoded()
        XCTAssertNil(plain.castConfig); XCTAssertNil(plain.playerProfile)
        let topic = try JSONDecoder().decode(TopicDetail.self, from: Data(#"{"id":31,"name":"雾港","castConfig":\#(Self.config)}"#.utf8))
        XCTAssertEqual(topic.castConfig?.cast.first?.name, "阿岚")
        XCTAssertNil(try JSONDecoder().decode(TopicDetail.self, from: Data(#"{"id":31,"name":"雾港"}"#.utf8)).castConfig)
    }
    func testProfileSaveIsGatedAndSendsExactJSON() async throws {
        let transport = CastTestTransport()
        let off = try service(transport, enabled: [])
        do { try await off.saveCastProfile(runID: 50, profile: .init(name: "小舟", identityKey: "i_a"), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        try await service(transport, enabled: [.castProfile]).saveCastProfile(runID: 50, profile: .init(name: "小舟", identityKey: "i_a"), token: "synthetic-token")
        let last = await transport.requests.last
        let sent = try XCTUnwrap(last)
        XCTAssertEqual(sent.httpMethod, "POST"); XCTAssertEqual(sent.url?.path, "/api/play/run/profile")
        XCTAssertEqual(String(decoding: try XCTUnwrap(sent.httpBody), as: UTF8.self), #"{"identityKey":"i_a","name":"小舟","runId":50}"#)
    }
    func testVoiceLookupReturnsHTTPSOrNothing() async throws {
        let transport = CastTestTransport()
        let reads = try service(transport, enabled: [.reads])
        let url = try await reads.castVoice(topicID: 9, chapterID: 8, blockKey: "b1", token: "synthetic-token")
        XCTAssertEqual(url, "https://voice.test/b1.mp3")
        let lastQuery = await transport.requests.last?.url?.query
        let query = try XCTUnwrap(lastQuery)
        XCTAssertEqual(query, "blockKey=b1&chapterId=8&topicId=9")
        let missing = try await reads.castVoice(topicID: 9, chapterID: 8, blockKey: "none", token: "synthetic-token")
        XCTAssertNil(missing)
    }
    @MainActor func testCoordinatorKeepsLocalAnswerWhenSaveIsOffAndClearsOnInvalidate() async throws {
        let transport = CastTestTransport()
        let session = try PlayExperienceSession(accountID: 9, epoch: 1, namespace: "synthetic-cn", token: "synthetic-token")
        let model = PlayExperienceCoordinator(scope: .topic(9), service: try service(transport, enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(),
            pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
        await model.load()
        XCTAssertNotNil(model.castConfig); XCTAssertNil(model.castProfile)
        await model.saveCastProfile(name: "小舟", identityKey: "i_a")
        XCTAssertEqual(model.castProfile, CastPlayerProfile(name: "小舟", identityKey: "i_a")); XCTAssertTrue(model.castProfileLocalOnly)
        let posts = await transport.requests.filter { $0.httpMethod == "POST" }
        XCTAssertTrue(posts.isEmpty)
        model.invalidate()
        XCTAssertNil(model.castConfig); XCTAssertNil(model.castProfile)
    }

    private func service(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability>) throws -> PlayExperienceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://cast.test")!), transport: transport, enabled: enabled)
    }
    private func wire(_ source: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(source.utf8)) }
    private func snapshot() throws -> PlaySnapshot {
        let data = #"{"topicId":9,"mode":1,"playable":true,"registered":true,"nodes":[],"chapters":[{"chapterId":8,"name":"Chapter"}]}"#
        return try PlaySnapshot(scope: .topic(9), result: wire(data).decoded())
    }
}
private actor CastTestTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.path {
        case "/api/play/run/profile": return (Data(#"{"code":200,"data":null}"#.utf8), 200)
        case "/api/topic/cast/voice":
            let ok = request.url?.query?.contains("blockKey=b1") == true
            return (Data((ok ? #"{"code":200,"data":{"url":"https://voice.test/b1.mp3"}}"# : #"{"code":200,"data":{"url":""}}"#).utf8), 200)
        default:
            return (Data(("{\"code\":200,\"data\":{\"topicId\":9,\"mode\":1,\"registered\":true,\"playable\":true,\"total\":1,\"doneCount\":0,\"nodes\":[{\"nodeId\":1,\"chapterId\":8,\"done\":false,\"validationMethod\":1}],\"chapters\":[{\"chapterId\":8,\"name\":\"Synthetic chapter\"}],\"castConfig\":" + CastContractsTests.config + "}}").utf8), 200)
        }
    }
}

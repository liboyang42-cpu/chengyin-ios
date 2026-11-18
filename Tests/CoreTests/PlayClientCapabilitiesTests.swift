import XCTest
@testable import QuestifyCore

/// The advanced start declares the complete iOS capability list, so a declared iOS client is
/// never refused for content it renders, and role views / letter pools are allowed to start.
@available(macOS 14.0, *)
@MainActor final class PlayClientCapabilitiesTests: XCTestCase {
    func testEveryNativePlayKitIsDeclaredWithServerSectionNaming() {
        let keys = Set(PlayClientCapabilities.keys)
        for kind in PlayKitScreenKind.allCases {
            XCTAssertTrue(keys.contains("game." + kind.rawValue.lowercased()), kind.rawValue)
        }
        XCTAssertTrue(keys.contains("game.hiddenobject"))
        XCTAssertTrue(keys.contains("game.blindtaste"))
    }

    func testStationAndFeatureKeysCoverWhatIOSCompletes() {
        let keys = Set(PlayClientCapabilities.keys)
        let expected: Set<String> = [
            "station.list", "media.image", "media.audio", "media.photo", "location.gps",
            "answer.arrive", "answer.gps", "answer.text", "answer.choice", "answer.photo", "answer.scan",
            "answer.preference", "answer.sensor", "answer.estimate", "answer.pricePair", "answer.hiddenObject",
            "sensor.still", "sensor.filter_shot", "hangman.pool", "qa.letterPool", "role.views",
        ]
        XCTAssertTrue(keys.isSuperset(of: expected), "missing: \(expected.subtracting(keys).sorted())")
        // Route-level and not-yet-native capabilities are never claimed.
        for absent in ["game.teamCooperation", "route.branch", "theme.runtime", "chapter.blocks"] {
            XCTAssertFalse(keys.contains(absent), absent)
        }
        XCTAssertEqual(PlayClientCapabilities.keys, PlayClientCapabilities.keys.sorted())
        XCTAssertEqual(Set(PlayClientCapabilities.keys).count, PlayClientCapabilities.keys.count)
    }

    func testTokensUseKeyAtVersion() {
        XCTAssertTrue(PlayClientCapabilities.tokens.allSatisfy { $0.hasSuffix("@1") && !$0.hasPrefix("@") })
        XCTAssertEqual(PlayClientCapabilities.declaration(["hangman.pool", "game.hangman"]), "game.hangman@1,hangman.pool@1")
        let fields = PlayClientCapabilities.startFields(clientVersion: "9.9")
        XCTAssertEqual(fields["clientPlatform"], .string("ios"))
        XCTAssertEqual(fields["clientVersion"], .string("9.9"))
        XCTAssertNil(PlayClientCapabilities.startFields(clientVersion: nil)["clientVersion"])
    }

    func testAdvancedStartSendsTheDeclaration() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/fixture/api/play/advanced/start"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200)
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: wire, enabled: [.reads, .advanced])
        _ = try await service.startAdvanced(activityID: 41, topicID: 71, nodeID: 701, token: "synthetic")
        let body = try XCTUnwrap(wire.requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["clientPlatform"] as? String, "ios")
        XCTAssertEqual(json["nodeId"] as? Int, 701)
        let declared = try XCTUnwrap(json["supportedCapabilities"] as? [String])
        XCTAssertEqual(declared, PlayClientCapabilities.tokens)
        for key in ["role.views@1", "hangman.pool@1", "qa.letterPool@1", "game.hangman@1"] {
            XCTAssertTrue(declared.contains(key), key)
        }
    }
}

import XCTest
@testable import QuestifyCore

private let creatorCompareJSON = #"{"compare":{"enabled":true,"prompt":"Mark what changed","left":{"label":"Original","items":[{"id":"L2","time":"08:00","text":"Gate opened"},{"id":"L1","time":"09:00","text":"Bell rang"}]},"right":{"label":"Revised","items":[{"id":"R2","time":"08:00","text":"Gate closed"},{"id":"R1","time":"09:00","text":"Bell rang"}]},"answer":["R2","L2"],"xp":5}}"#

final class TemplateCompareTests: XCTestCase {
    private func draft() throws -> TemplateAdvancedDraft { try .init(raw: creatorCompareJSON) }
    func testPublicConfigurationOnlyIncludesQuestionAndPreservesOrder() throws {
        let draft = try draft(); let projection = try draft.comparePublicConfiguration()
        XCTAssertEqual(Set(projection.object?.keys.map { $0 } ?? []), ["enabled", "prompt", "maxAttempts", "left", "right"])
        XCTAssertNil(projection.object?["answer"]); XCTAssertNil(projection.object?["xp"]); XCTAssertNil(projection.object?["effects"])
        XCTAssertEqual(projection.object?["maxAttempts"], .number(0))
        XCTAssertEqual(projection.object?["left"]?.object?["items"]?.array?.first?.object?["id"], .string("L2"))
    }
    func testUnlimitedOmissionNullAndCapsRoundtripWithoutInventedZero() throws {
        var draft = try draft()
        XCTAssertNil(draft.value["compare"]?.object?["maxAttempts"])
        let serialized = try draft.serialize(); XCTAssertEqual(try TemplateAdvancedDraft(raw: serialized).serialize(), serialized)
        for cap in [TemplateAuthoringJSON.null, .number(1), .number(10)] {
            draft.set("compare", "maxAttempts", cap); XCTAssertTrue(draft.creatorIssues(.compare).isEmpty)
            XCTAssertNoThrow(try draft.serialize())
        }
        for cap in [TemplateAuthoringJSON.number(0), .number(-1), .number(11), .number(1.5), .string("")] {
            draft.set("compare", "maxAttempts", cap); XCTAssertFalse(draft.creatorIssues(.compare).isEmpty)
        }
    }
    func testQuestionOrderAndStableIDsSurviveReopen() throws {
        let restored = try TemplateAdvancedDraft(raw: draft().serialize())
        XCTAssertEqual(restored.value["compare"]?.object?["left"]?.object?["items"]?.array?.compactMap { $0.object?["id"]?.string }, ["L2", "L1"])
        XCTAssertEqual(restored.value["compare"]?.object?["answer"]?.array?.compactMap(\.string), ["R2", "L2"])
    }
    func testCrossSideDuplicateIDsFailClosed() throws {
        var draft = try draft()
        draft.setCreatorValue(.compare, path: [.field("right"), .field("items"), .index(0), .field("id")], entry: .string("L2"))
        XCTAssertTrue(draft.creatorIssues(.compare).contains { $0.code == "duplicate" })
        XCTAssertThrowsError(try draft.serialize())
    }
    func testAnswersMustBeNonemptyUniqueKnownIDsFromEitherSide() throws {
        for answer in [TemplateAuthoringJSON.array([]), .array([.string("L2"), .string("L2")]), .array([.string("missing")]), .array([.number(3)])] {
            var draft = try draft(); draft.set("compare", "answer", answer); XCTAssertThrowsError(try draft.serialize())
        }
        var draft = try draft(); draft.set("compare", "answer", .array([.string("L1"), .string("R1")]))
        XCTAssertNoThrow(try draft.serialize())
    }
    func testImportedPublicProjectionNeverGetsAnAnswerDefault() throws {
        let publicJSON = creatorCompareJSON.replacingOccurrences(of: ",\"answer\":[\"R2\",\"L2\"]", with: "")
        let draft = try TemplateAdvancedDraft(raw: publicJSON)
        XCTAssertEqual(draft.value["compare"]?.object?["answer"], .null)
        XCTAssertThrowsError(try draft.serialize())
    }
    func testExactUTF16BoundsAndMinimumSideCount() throws {
        for (path, value) in [([TemplateCreatorPath.field("prompt")], TemplateAuthoringJSON.string(String(repeating: "x", count: 201))),
            ([.field("left"), .field("label")], .string(String(repeating: "x", count: 21))),
            ([.field("left"), .field("items"), .index(0), .field("time")], .string(String(repeating: "x", count: 17))),
            ([.field("left"), .field("items"), .index(0), .field("text")], .string(String(repeating: "🎨", count: 101))),
            ([.field("left"), .field("items"), .index(0), .field("id")], .string(String(repeating: "x", count: 33))),
            ([.field("left"), .field("items")], .array([]))] {
            var draft = try draft(); draft.setCreatorValue(.compare, path: path, entry: value)
            XCTAssertThrowsError(try draft.serialize())
        }
    }
    func testEffectsNeverSilentlyBecomeActive() throws {
        var draft = try draft()
        for effects in [TemplateAuthoringJSON.null, .array([])] { draft.set("compare", "effects", effects); XCTAssertNoThrow(try draft.serialize()) }
        draft.set("compare", "effects", .array([.object(["op": .string("INC"), "var": .string("counter.sample"), "value": .number(1)])]))
        XCTAssertThrowsError(try draft.serialize())
    }
    func testUnknownNestedFieldsSurviveLeafEditAndSnapshotButBlockPublication() throws {
        var draft = try draft()
        let path: [TemplateCreatorPath] = [.field("left"), .field("items"), .index(0)]
        draft.setCreatorValue(.compare, path: path + [.field("future")], entry: .string("preserve"))
        draft.setCreatorValue(.compare, path: path + [.field("text")], entry: .string("Changed locally"))
        let restored = try JSONDecoder().decode(TemplateAdvancedDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.creatorValue(.compare, path: path + [.field("future")]), .string("preserve"))
        XCTAssertEqual(restored.creatorValue(.compare, path: path + [.field("id")]), .string("L2"))
        XCTAssertThrowsError(try restored.serialize())
    }
    func testCompareCoexistsWithExistingGamesAndPresentationModes() throws {
        var draft = try draft(); draft.setGameEnabled(.coin, true); draft.setGameEnabled(.dice, true)
        let compare = draft.value["compare"]
        draft.setGameEnabled(.coin, false); XCTAssertEqual(draft.value["compare"], compare); XCTAssertTrue(draft.enabled("diceRoll"))
        for mode in ["inline", "fullscreen"] { draft.setPresentation(mode); XCTAssertNoThrow(try draft.serialize()) }
    }
    func testAddRowAllocatesGlobalUniqueIDWithoutChangingExistingIDs() throws {
        var draft = try draft()
        let side = try XCTUnwrap(TemplateCreatorSchema.fields(.compare).first { $0.id == "left" })
        guard case .object(let fields) = side.kind else { return XCTFail("Missing side schema") }
        let items = try XCTUnwrap(fields.first { $0.id == "items" })
        draft.addCreatorRow(.compare, path: [.field("left"), .field("items")], field: items)
        draft.addCreatorRow(.compare, path: [.field("right"), .field("items")], field: items)
        let ids = ["left", "right"].flatMap { draft.value["compare"]?.object?[$0]?.object?["items"]?.array ?? [] }.compactMap { $0.object?["id"]?.string }
        XCTAssertEqual(ids.count, 6); XCTAssertEqual(Set(ids).count, 6); XCTAssertTrue(ids.contains("L2")); XCTAssertTrue(ids.contains("R2"))
    }
    func testLocalRehearsalUsesWholeSetAndNeverChangesDraftRewardsOrReadiness() throws {
        let draft = try draft(); let before = draft.value; var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.compare, draft: draft, selected: ["L2", "R2"]); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.evaluate(.compare, draft: draft, selected: ["L2"]); XCTAssertEqual(rehearsal.result, .missed)
        rehearsal.evaluate(.compare, draft: draft, selected: []); XCTAssertEqual(rehearsal.result, .missed)
        rehearsal.evaluate(.compare, draft: draft, selected: ["missing"]); XCTAssertEqual(rehearsal.result, .invalid)
        XCTAssertEqual(draft.value, before)
    }
}

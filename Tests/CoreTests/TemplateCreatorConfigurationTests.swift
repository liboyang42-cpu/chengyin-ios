import XCTest
@testable import QuestifyCore

final class TemplateCreatorConfigurationTests: XCTestCase {
    private func fixture(_ family: TemplateCreatorFamily) throws -> TemplateAdvancedDraft {
        let raw: String
        switch family {
        case .compare: raw = #"{"compare":{"enabled":true,"prompt":"Mark changes","left":{"label":"Left","items":[{"id":"l1","time":"09:00","text":"Open"},{"id":"l2","time":"10:00","text":"Bell"}]},"right":{"label":"Right","items":[{"id":"r1","time":"09:00","text":"Closed"},{"id":"r2","time":"10:00","text":"Bell"}]},"answer":["l1","r1"]}}"#
        case .random: raw = #"{"random":{"deckName":"Sample cards","drawCount":1,"items":[{"id":"card_1","label":"Look up","weight":1,"content":"Observe the sky"}],"enabled":true}}"#
        case .branch: raw = #"{"branch":{"startStepId":"start","steps":[{"id":"start","title":"Choose a path","body":"Choose the exit","terminal":false,"options":[{"id":"go","label":"Continue","nextStepId":"end","score":0,"effects":[]}]},{"id":"end","title":"End","body":"Finished","terminal":true,"outcomeCode":"COMPLETED","outcomeLabel":"Finished","options":[]}],"enabled":true}}"#
        case .leaderboard: raw = #"{"leaderboard":{"metric":"SCORE","scope":"ACTIVITY","limit":10,"enabled":true}}"#
        case .multiplayer: raw = #"{"multiplayer":{"mode":"SEQUENTIAL","minPlayers":2,"maxPlayers":4,"assignment":"AUTO","requiredTurns":2,"unitScore":0,"roles":[{"id":"player","label":"Player","min":1,"max":4}],"turnOrder":["player"],"enabled":true}}"#
        case .timeWindow: raw = #"{"timeWindow":{"title":"Night station","openFrom":"23:00","openTo":"02:00","enabled":true}}"#
        case .blindTaste: raw = #"{"blindTaste":{"title":"Name the sample","answerKey":"A","options":[{"key":"A","label":"Apple"},{"key":"B","label":"Pear"}],"enabled":true}}"#
        case .silentOrder: raw = #"{"silentOrder":{"title":"Quiet order","rule":"Point to your choice","limitSeconds":60,"enabled":true}}"#
        case .diyName: raw = #"{"diyName":{"title":"Name your work","maxLength":16,"suggestions":["Morning"],"enabled":true}}"#
        case .musicCorner: raw = #"{"musicCorner":{"title":"Listen here","trackName":"Sample track","durationSeconds":10,"audioUrl":"https://example.com/sample.mp3","enabled":true}}"#
        case .steps: raw = #"{"steps":{"goal":100,"enabled":true}}"#
        case .dailySign: raw = #"{"dailySign":{"signer":"Sample","sealText":"Today","poems":[["Look up","Take your time"]],"enabled":true}}"#
        case .slowTask: raw = #"{"slowTask":{"title":"Return tomorrow","waitDays":1,"unlockText":"Look again","enabled":true}}"#
        case .estimate: raw = #"{"estimate":{"title":"Estimate the count","min":0,"max":100,"answer":50,"tolerance":5,"enabled":true}}"#
        case .pricePair: raw = #"{"pricePair":{"title":"Choose the matching image","items":[{"id":"a","name":"A","imageUrl":"https://example.com/a.png","correct":true},{"id":"b","name":"B","correct":false},{"id":"c","name":"C","correct":false}],"enabled":true}}"#
        case .hiddenObject: raw = #"{"hiddenObject":{"title":"Find the shapes","imageUrl":"https://example.com/shapes.png","hotspots":[{"id":"a","label":"Circle","x":0.2,"y":0.2,"r":0.08},{"id":"b","label":"Square","x":0.6,"y":0.2,"r":0.08},{"id":"c","label":"Triangle","x":0.5,"y":0.7,"r":0.08}],"enabled":true}}"#
        case .predict: raw = #"{"predict":{"question":"Which color will appear?","closeAtHour":20,"revealDays":1,"revealHour":20,"options":[{"key":"A","label":"Blue"},{"key":"B","label":"Green"}],"enabled":true}}"#
        case .qa: raw = #"{"qa":{"mode":"TYPE","title":"Name the color","answerText":"Blue","enabled":true}}"#
        case .scan: raw = #"{"scan":{"kind":"TEXT","reply":"Welcome","enabled":true}}"#
        case .album: raw = #"{"album":{"images":[{"url":"https://example.com/a.png","line":"Morning light"}],"enabled":true}}"#
        case .profile: raw = #"{"profile":{"questions":[{"key":"name","label":"Character name","kind":"text","maxLength":12,"required":true}],"enabled":true}}"#
        case .photoCheck: raw = #"{"photoCheck":{"title":"Find a circle","requirement":"A clear circular object","minConfidence":60,"maxTries":3,"fallback":"retake","enabled":true}}"#
        case .check: raw = #"{"check":{"checkId":"check_sample","tier":"medium","skill":"Observation","successText":"You notice it","failText":"Look again","successEffects":[{"op":"INC","var":"counter.observations","value":1}],"failEffects":[],"mods":[],"enabled":true}}"#
        case .note: raw = #"{"note":{"title":"Leave a note","prompt":"What did you notice?","maxLength":40,"presets":["Look up"],"showPrevious":3,"enabled":true}}"#
        case .typeIn: raw = #"{"typeIn":{"title":"Type the line","target":"Hello world","seconds":10,"caseSensitive":false,"tries":3,"enabled":true}}"#
        }
        return try TemplateAdvancedDraft(raw: raw)
    }
    func testAllTwentyFiveFamiliesSerializeReopenAndReserialize() throws {
        XCTAssertEqual(TemplateCreatorFamily.allCases.count, 25)
        for family in TemplateCreatorFamily.allCases {
            let draft = try fixture(family)
            XCTAssertTrue(draft.creatorIssues(family).isEmpty, "\(family): \(draft.creatorIssues(family))")
            XCTAssertTrue(draft.creatorUnknownIssues.isEmpty, "\(family)")
            let first = try draft.serialize()
            let reopened = try TemplateAdvancedDraft(raw: first)
            XCTAssertEqual(try reopened.serialize(), first, family.rawValue)
        }
    }
    func testThirtyEightSectionsHaveStructuredAuthoring() {
        let supported = Set(TemplateCreatorFamily.allCases.map(\.rawValue) + TemplateAdvancedGame.allCases.map(\.section) + ["timer"])
        XCTAssertEqual(supported.count, 38)
        XCTAssertEqual(Set(TemplateAdvancedDraft.defaults.keys).subtracting(["schemaVersion"]), supported)
        XCTAssertFalse(supported.contains("gameTimer")); XCTAssertFalse(supported.contains("stickerBook"))
    }
    func testEveryTopLevelNumberRejectsOutOfBoundsAndBlank() throws {
        for family in TemplateCreatorFamily.allCases {
            for field in TemplateCreatorSchema.fields(family) {
                guard case .number(let minimum, let maximum, _) = field.kind else { continue }
                for value in [TemplateAuthoringJSON.number(minimum.nextDown), .number(maximum.nextUp), .string("")] {
                    var draft = try fixture(family); draft.set(family.rawValue, field.id, value)
                    XCTAssertTrue(draft.creatorIssues(family).contains(where: { $0.path == field.id && $0.code == "range" }), "\(family).\(field.id)")
                }
            }
        }
    }
    func testStringLimitsCountUTF16Units() throws {
        var draft = try fixture(.note); draft.set("note", "title", .string(String(repeating: "🎨", count: 33)))
        XCTAssertTrue(draft.creatorIssues(.note).contains { $0.path == "title" && $0.code == "length" })
    }
    func testSourceWireValuesDoNotUseDisplayTranslations() throws {
        var draft = try fixture(.leaderboard); draft.set("leaderboard", "metric", .string("得分"))
        XCTAssertFalse(draft.creatorIssues(.leaderboard).isEmpty)
        draft.set("leaderboard", "metric", .string("SCORE")); XCTAssertTrue(draft.creatorIssues(.leaderboard).isEmpty)
    }
    func testCoexistingFamiliesAndOldGameSelectionPreserveModifiers() throws {
        var draft = try fixture(.blindTaste); draft.setCreatorEnabled(.timeWindow, true); draft.setGameEnabled(.quiet, true)
        XCTAssertTrue(draft.enabled("blindTaste")); XCTAssertTrue(draft.enabled("timeWindow")); XCTAssertTrue(draft.enabled("quietHold")); XCTAssertTrue(draft.issues.isEmpty)
    }
    func testUnknownNestedFieldsSurviveSnapshotAndBlockReserialization() throws {
        var draft = try fixture(.random)
        draft.setCreatorValue(.random, path: [.field("items"), .index(0), .field("future")], entry: .object(["keep": .number(7)]))
        draft.setCreatorValue(.random, path: [.field("items"), .index(0), .field("label")], entry: .string("Edited"))
        let reopened = try JSONDecoder().decode(TemplateAdvancedDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(reopened.creatorValue(.random, path: [.field("items"), .index(0), .field("future")]), .object(["keep": .number(7)]))
        XCTAssertThrowsError(try reopened.serialize())
    }
    func testDisabledUnknownAndRootScalarPreservedFailClosed() throws {
        var draft = try TemplateAdvancedDraft(raw: #"{"futureRoot":[1,2]}"#)
        XCTAssertEqual(draft.value["futureRoot"], .array([.number(1), .number(2)])); XCTAssertThrowsError(try draft.serialize())
        draft = try fixture(.note); draft.set("random", "future", .string("retain"))
        XCTAssertThrowsError(try draft.serialize())
    }
    func testImportedProjectionCannotInventSecretAnswers() throws {
        let draft = try TemplateAdvancedDraft(raw: #"{"estimate":{"enabled":true,"title":"Count","min":0,"max":100}}"#)
        XCTAssertEqual(draft.value["estimate"]?.object?["answer"], .null)
        XCTAssertThrowsError(try draft.serialize())
    }
    func testTerminalGraphMustBeReachableAndCannotHaveOutgoingOptions() throws {
        var draft = try fixture(.branch)
        draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field("options"), .index(0), .field("nextStepId")], entry: .string("start"))
        XCTAssertTrue(draft.creatorIssues(.branch).contains { $0.code == "unreachable" })
        draft = try fixture(.branch)
        draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field("terminal")], entry: .bool(true))
        XCTAssertTrue(draft.creatorIssues(.branch).contains { $0.code == "branch" })
    }
    func testNightWindowCrossesMidnightButEqualTimesReject() throws {
        var draft = try fixture(.timeWindow); XCTAssertTrue(draft.creatorIssues(.timeWindow).isEmpty)
        draft.set("timeWindow", "openTo", .string("23:00")); XCTAssertFalse(draft.creatorIssues(.timeWindow).isEmpty)
    }
    func testSourceStateTagAndLuckEffects() throws {
        var draft = try fixture(.check)
        draft.set("check", "successEffects", .array([.object(["op": .string("ADD_TAG"), "value": .string("tag.observant")])]))
        XCTAssertTrue(draft.creatorIssues(.check).isEmpty)
        draft.set("check", "successEffects", .array([.object(["op": .string("SET"), "var": .string("sys.luck"), "value": .number(2)])]))
        XCTAssertFalse(draft.creatorIssues(.check).isEmpty)
    }
    func testPhotoCheckLegacyRuleIsPreservedAndBlocked() throws {
        var draft = try fixture(.photoCheck); draft.set("photoCheck", "rule", .object(["mode": .string("any")]))
        XCTAssertThrowsError(try draft.serialize()); XCTAssertNotNil(draft.value["photoCheck"]?.object?["rule"])
    }
    func testProfileOptionKeysAreUniqueAcrossQuestions() throws {
        var draft = try fixture(.profile)
        func question(_ key: String) -> TemplateAuthoringJSON { .object(["key": .string(key), "label": .string("Choose"), "kind": .string("pick"), "options": .array([.object(["key": .string("same"), "label": .string("A")]), .object(["key": .string(key + "_b"), "label": .string("B")])])]) }
        draft.set("profile", "questions", .array([question("one"), question("two")]))
        XCTAssertTrue(draft.creatorIssues(.profile).contains { $0.code == "duplicate" })
    }
    func testMissingProviderDoesNotPreventAuthoringOrInventVerification() throws {
        for family: TemplateCreatorFamily in [.steps, .photoCheck, .scan, .slowTask, .multiplayer, .leaderboard] {
            let draft = try fixture(family); XCTAssertNoThrow(try draft.serialize())
            var rehearsal = TemplateCreatorRehearsal(); rehearsal.evaluate(family, draft: draft)
            XCTAssertEqual(rehearsal.result, .providerRequired)
        }
    }
    func testLocalRehearsalAnswersAndReset() throws {
        var rehearsal = TemplateCreatorRehearsal(); let draft = try fixture(.estimate)
        rehearsal.evaluate(.estimate, draft: draft, text: "55"); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.evaluate(.estimate, draft: draft, text: "56"); XCTAssertEqual(rehearsal.result, .missed)
        rehearsal.reset(); XCTAssertEqual(rehearsal.result, .ready); XCTAssertTrue(rehearsal.visited.isEmpty)
    }
    func testLocalTypingNeedsStartAndRespectsTiming() throws {
        let draft = try fixture(.typeIn); var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.typeIn, draft: draft, text: "hello world"); XCTAssertEqual(rehearsal.result, .invalid)
        rehearsal.evaluate(.typeIn, draft: draft, text: "hello world", elapsed: 10); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.evaluate(.typeIn, draft: draft, text: "hello world", elapsed: 10.1); XCTAssertEqual(rehearsal.result, .missed)
    }
    func testLocalBranchCannotJumpToAnUnlistedOption() throws {
        let draft = try fixture(.branch); var rehearsal = TemplateCreatorRehearsal(); rehearsal.startBranch(draft)
        rehearsal.chooseBranch("invalid", draft: draft); XCTAssertEqual(rehearsal.branchStepID, "start")
        rehearsal.chooseBranch("go", draft: draft); XCTAssertEqual(rehearsal.branchStepID, "end"); XCTAssertEqual(rehearsal.result, .matched)
    }
    func testEmptyMediaIsOmittedAndNormalizedNumbersRemainNumbers() throws {
        var draft = try fixture(.photoCheck); draft.set("photoCheck", "minConfidence", .string(" 60 "))
        let result = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(result.value["photoCheck"]?.object?["minConfidence"], .number(60))
        let wire = try JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: Data(draft.serialize().utf8))
        XCTAssertNil(wire["photoCheck"]?.object?["frameUrl"]); XCTAssertNil(wire["photoCheck"]?.object?["frameOpacity"])
    }
    func testHiddenObjectLocalHitsRejectInvalidCoordinatesAndReset() throws {
        let draft = try fixture(.hiddenObject); var rehearsal = TemplateCreatorRehearsal()
        rehearsal.tapHiddenObject(draft: draft, x: -1, y: 0); XCTAssertEqual(rehearsal.result, .invalid)
        rehearsal.tapHiddenObject(draft: draft, x: 0.2, y: 0.2); XCTAssertEqual(rehearsal.foundTargets, ["a"])
        rehearsal.tapHiddenObject(draft: draft, x: 0.6, y: 0.2)
        rehearsal.tapHiddenObject(draft: draft, x: 0.5, y: 0.7); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.reset(); XCTAssertTrue(rehearsal.foundTargets.isEmpty)
    }

    func testImportedRowNumbersAndEffectValuesAreNotInvented() throws {
        var draft = try fixture(.hiddenObject)
        draft.setCreatorValue(.hiddenObject, path: [.field("hotspots"), .index(0), .field("x")], entry: nil)
        XCTAssertTrue(draft.creatorIssues(.hiddenObject).contains { $0.code == "required" })
        draft = try fixture(.random)
        draft.setCreatorValue(.random, path: [.field("items"), .index(0), .field("weight")], entry: nil)
        XCTAssertTrue(draft.creatorIssues(.random).contains { $0.code == "required" })
        draft = try fixture(.check)
        draft.setCreatorValue(.check, path: [.field("successEffects"), .index(0), .field("value")], entry: nil)
        XCTAssertTrue(draft.creatorIssues(.check).contains { $0.code == "required" })
    }

}

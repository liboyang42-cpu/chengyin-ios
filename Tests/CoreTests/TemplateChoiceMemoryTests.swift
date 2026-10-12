import XCTest
@testable import QuestifyCore

final class TemplateChoiceMemoryTests: XCTestCase {
    private let qaPath: [TemplateCreatorPath] = [.field("options"), .index(0)]
    private let profilePath: [TemplateCreatorPath] = [.field("questions"), .index(0), .field("options"), .index(0)]
    private func fixture(_ family: TemplateCreatorFamily = .qa) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(family, true)
        if family == .qa {
            draft.set("qa", "mode", .string("PICK")); draft.set("qa", "title", .string("Choose"))
            draft.set("qa", "options", .array([.object(["id": .string("A"), "label": .string("One"), "correct": .bool(true), "effects": .array([])]), .object(["id": .string("B"), "label": .string("Two"), "correct": .bool(false), "effects": .array([])])]))
        } else {
            draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("label")], entry: .string("Role"))
            draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("kind")], entry: .string("pick"))
            draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("options")], entry: .array([.object(["key": .string("A"), "label": .string("One"), "effects": .array([])]), .object(["key": .string("B"), "label": .string("Two"), "effects": .array([])])]))
        }
        return draft
    }
    private func effect(_ operation: String, _ value: TemplateAuthoringJSON, variable: String = "") -> TemplateAuthoringJSON { .object(["op": .string(operation), "var": .string(variable), "value": value]) }
    private func effects(_ draft: TemplateAdvancedDraft, family: TemplateCreatorFamily = .qa, path: [TemplateCreatorPath]? = nil) -> [TemplateAuthoringJSON] { draft.creatorValue(family, path: (path ?? qaPath) + [.field("effects")])?.array ?? [] }
    func testOnlyQAAndProfileOptionPathsAreAccepted() {
        XCTAssertTrue(TemplateChoiceMemory.isOptionPath(.qa, qaPath)); XCTAssertTrue(TemplateChoiceMemory.isOptionPath(.profile, profilePath))
        for path in [[], [.field("options")], [.field("options"), .index(-1)], qaPath + [.field("effects")]] { XCTAssertFalse(TemplateChoiceMemory.isOptionPath(.qa, path)) }
        XCTAssertFalse(TemplateChoiceMemory.isOptionPath(.branch, profilePath))
    }
    func testOpeningShowsExistingMemoryTagsWithoutRewritingDuplicates() {
        var draft = fixture(); draft.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array([effect("ADD_TAG", .string("tag.m_aaaaaa")), effect("ADD_TAG", .string("tag.m_bbbbbb"))]))
        let before = draft, memory = TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath)
        XCTAssertEqual(memory.tags, ["tag.m_aaaaaa", "tag.m_bbbbbb"]); XCTAssertTrue(memory.isEnabled); XCTAssertEqual(draft, before)
    }
    func testEnableThenDisableUsesOnlyExistingEffectWireShapeForBothFamilies() throws {
        for family in [TemplateCreatorFamily.qa, .profile] {
            let path = family == .qa ? qaPath : profilePath, original = fixture(family)
            let on = try XCTUnwrap(TemplateChoiceMemory(original, family: family, optionPath: path).applying(enabled: true, to: original, proposedTag: "tag.m_abc123"))
            XCTAssertEqual(effects(on, family: family, path: path), [effect("ADD_TAG", .string("tag.m_abc123"))])
            let off = try XCTUnwrap(TemplateChoiceMemory(on, family: family, optionPath: path).applying(enabled: false, to: on)); XCTAssertEqual(off, original)
        }
    }
    func testEnableReplacesAllMemoryEffectsAndPreservesOtherEffectsInOrder() throws {
        var draft = fixture(); let increment = effect("INC", .number(2), variable: "counter.energy"), otherTag = effect("ADD_TAG", .string("tag.friend")), similar = effect("SET", .string("tag.m_aaaaaa"), variable: "clue.note")
        draft.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array([increment,effect("ADD_TAG", .string("tag.m_aaaaaa")),otherTag,similar,effect("ADD_TAG", .string("tag.m_bbbbbb"))]))
        let next = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).applying(enabled: true, to: draft, proposedTag: "tag.m_cccccc"))
        XCTAssertEqual(effects(next), [increment,otherTag,similar,effect("ADD_TAG", .string("tag.m_cccccc"))])
    }
    func testOffRecognizesAnyMemoryPrefixButLeavesSimilarNonMemoryValues() throws {
        var draft = fixture(); let other = [effect("ADD_TAG", .string("tag.manual")),effect("INC", .string("tag.m_keep")),effect("ADD_TAG", .string("tag.mixed"))]
        draft.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array([effect("ADD_TAG", .string("tag.m_old_legacy"))]+other))
        let next = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).applying(enabled: false, to: draft)); XCTAssertEqual(effects(next), other)
    }
    func testSixCharacterGeneratedTagsAreValidAndDifferentAcrossOptions() throws {
        var draft = fixture(); let first = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).applying(enabled: true, to: draft)); draft = first
        let otherPath: [TemplateCreatorPath] = [.field("options"), .index(1)]
        draft = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: otherPath).applying(enabled: true, to: draft))
        let tags = [TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).tags[0],TemplateChoiceMemory(draft, family: .qa, optionPath: otherPath).tags[0]]
        XCTAssertEqual(Set(tags).count, 2); for tag in tags { XCTAssertNotNil(tag.range(of: "^tag\\.m_[a-z][a-z0-9]{5}$", options: .regularExpression)) }
    }
    func testInvalidOrCrossDraftCollisionCandidateCannotBeWritten() {
        var draft = fixture(); draft.set("note", "future", .string("tag.m_aaaaaa")); let memory = TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath)
        for value in ["tag.m_aaaaaa", "tag.m_123456", "tag.other", "tag.m_a", "tag.m_ABCDEF"] { XCTAssertNil(memory.applying(enabled: true, to: draft, proposedTag: value)) }
    }
    func testSixteenEffectCapacityNeverDeletesUnrelatedEffectsAndOffStillWorks() throws {
        var draft = fixture(); let others = (0..<16).map { effect("INC", .number(Double($0)), variable: "counter.energy") }
        draft.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array(others)); let full = TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath)
        XCTAssertFalse(full.canEnable); XCTAssertNil(full.applying(enabled: true, to: draft))
        draft.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array(others+[effect("ADD_TAG", .string("tag.m_aaaaaa"))]))
        let off = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).applying(enabled: false, to: draft)); XCTAssertEqual(effects(off), others)
    }
    func testInactiveFamiliesModesAndUnsupportedLegacyEffectsDenyChanges() {
        var draft = fixture(); draft.set("qa", "mode", .string("TYPE")); XCTAssertFalse(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).canEdit)
        draft = fixture(.profile); draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("kind")], entry: .string("text")); XCTAssertFalse(TemplateChoiceMemory(draft, family: .profile, optionPath: profilePath).canEdit)
        draft = fixture(); draft.setCreatorEnabled(.qa, false); XCTAssertFalse(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).canEdit)
        for raw in [TemplateAuthoringJSON.string("legacy"), .array([.number(2)]), .array([effect("ADD_TAG", .array([]))])] { draft = fixture(); draft.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: raw); XCTAssertFalse(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).isSupported) }
    }
    func testNestedScopeAndSnapshotRejectRenameReorderAndSameOptionEffectChanges() throws {
        let draft = fixture(), memory = TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath)
        var renamed = draft; renamed.setCreatorValue(.qa, path: qaPath + [.field("label")], entry: .string("Other"))
        XCTAssertNotEqual(TemplateChoiceMemory(renamed, family: .qa, optionPath: qaPath).scopeFingerprint, memory.scopeFingerprint); XCTAssertNil(memory.applying(enabled: true, to: renamed))
        let on = try XCTUnwrap(memory.applying(enabled: true, to: draft, proposedTag: "tag.m_aaaaaa"))
        XCTAssertEqual(TemplateChoiceMemory(on, family: .qa, optionPath: qaPath).scopeFingerprint, memory.scopeFingerprint); XCTAssertNil(memory.applying(enabled: false, to: on))
    }
    func testUnknownOptionFieldsAndOtherFamiliesSurviveMemoryEdits() throws {
        var draft = fixture(); draft.setCreatorValue(.qa, path: qaPath + [.field("future")], entry: .string("keep")); draft.set("timer", "enabled", .bool(true)); let before = draft
        let next = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).applying(enabled: true, to: draft, proposedTag: "tag.m_aaaaaa"))
        for key in ["id", "label", "correct", "future"] { XCTAssertEqual(next.creatorValue(.qa, path: qaPath)?.object?[key], before.creatorValue(.qa, path: qaPath)?.object?[key]) }
        XCTAssertEqual(next.value["timer"], before.value["timer"]); XCTAssertEqual(next.creatorValue(.qa, path: [.field("options"), .index(1)]), before.creatorValue(.qa, path: [.field("options"), .index(1)]))
    }
    func testMemoryConfigurationSerializesAndRoundTripsWithoutApplyingPlayerEffects() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateChoiceMemory(draft, family: .qa, optionPath: qaPath).applying(enabled: true, to: draft, proposedTag: "tag.m_aaaaaa"))
        XCTAssertTrue(next.creatorIssues(.qa).isEmpty); let decoded = try TemplateAdvancedDraft(raw: next.serialize()); XCTAssertEqual(TemplateChoiceMemory(decoded, family: .qa, optionPath: qaPath).tags, ["tag.m_aaaaaa"])
        var local = TemplateAuthoringDraft(title: "Memory"); local.advanced = next
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)); XCTAssertEqual(restored, local)
    }
}

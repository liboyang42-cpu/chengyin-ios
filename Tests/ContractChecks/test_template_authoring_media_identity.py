"""Offline source contracts for the dormant media lease, not Swift execution."""
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
IDENTITY = (ROOT / "Core/TemplateAuthoringMediaIdentity.swift").read_text()
SNAPSHOT = (ROOT / "Core/TemplateAuthoringMediaReferenceSnapshot.swift").read_text()


def section(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


class TemplateAuthoringMediaIdentitySourceContracts(unittest.TestCase):
    def test_identity_contains_all_freshness_dimensions_and_is_not_durable(self):
        identity = section(IDENTITY, "public struct TemplateAuthoringMediaSelectionIdentity", "/// Dormant identity seam")
        for field in ["owner", "editorID", "slot", "slotRevision", "selectionID"]:
            self.assertIn("public let " + field + ":", identity)
        self.assertNotIn("Codable", identity)
        self.assertIn("fileprivate init", identity)
        owner = section(IDENTITY, "public struct TemplateAuthoringMediaOwner", "public enum TemplateAuthoringMediaField")
        self.assertIn("session: TemplateAuthoringSession", owner)
        self.assertIn("draft: TemplateAuthoringIdentity", owner)

    def test_freshness_checks_every_dimension_before_single_use_consumption(self):
        current = section(IDENTITY, "public func isCurrent", "/// Consumes the identity once")
        for check in ["hasCurrentOwner()", "identity.owner == owner", "identity.editorID == editorID",
                      "$0.slot == identity.slot", "entry.revision == identity.slotRevision",
                      "entry.selectionID == identity.selectionID"]:
            self.assertIn(check, current)
        finish = section(IDENTITY, "public func finishSelection", "/// Cancels only this selection")
        self.assertLess(finish.index("guard isCurrent(identity)"), finish.index("selectionID = nil"))
        cancel = section(IDENTITY, "public func cancelSelection", "/// Explicit clear/replacement")
        self.assertIn("finishSelection(identity)", cancel)

    def test_start_requires_captured_target_and_has_no_uuid_only_bypass(self):
        self.assertNotIn("beginSelection(slotID:", IDENTITY)
        self.assertIn("public var visibleTargets: [TemplateAuthoringMediaTargetIdentity]", IDENTITY)
        target = section(IDENTITY, "public struct TemplateAuthoringMediaTargetIdentity", "/// In-memory callback identity only")
        for field in ["owner", "editorID", "slot", "slotRevision"]:
            self.assertIn("public let " + field + ":", target)
        self.assertIn("fileprivate init", target)
        begin = section(IDENTITY, "public func beginSelection", "public func isCurrent")
        for check in ["target.owner == owner", "target.editorID == editorID", "$0.slot == target.slot",
                      "$0.revision == target.slotRevision", "throw Failure.staleTarget"]:
            self.assertIn(check, begin)
        self.assertLess(begin.index("target.owner == owner"), begin.index("entries[index].selectionID = selectionID"))

    def test_story_matching_is_byte_sensitive_including_empty_row_fallback(self):
        self.assertNotIn("map(\\.wire)", SNAPSHOT)
        self.assertIn("if exactRows(loaded, stored)", SNAPSHOT)
        self.assertIn("return exactRows(serializedRows, stored)", SNAPSHOT)
        for exact in ["lhs.text.utf8.elementsEqual(rhs.text.utf8)",
                      "lhs.tag.utf8.elementsEqual(rhs.tag.utf8)", "image.utf8.elementsEqual(stored.utf8)"]:
            self.assertIn(exact, SNAPSHOT)

    def test_reference_and_topology_events_invalidate_pending_selections(self):
        change = section(IDENTITY, "public func referenceDidChange", "/// Keep stable IDs during moves")
        self.assertIn("revision = UUID()", change)
        self.assertIn("selectionID = nil", change)
        synchronize = section(IDENTITY, "public func synchronizeSlots", "/// Report structural edits")
        self.assertIn("catch { retire(); throw error }", synchronize)
        self.assertIn("guard slots != entries.map(\\.slot) else { return }", synchronize)
        self.assertIn("entries = slots.map { Entry(slot: $0) }", synchronize)
        explicit = section(IDENTITY, "public func topologyDidChange", "/// Explicitly close this editor lease")
        self.assertIn("entries = entries.map { Entry(slot: $0.slot) }", explicit)

    def test_owner_mismatch_and_failed_reset_retire_old_incarnation(self):
        retire = section(IDENTITY, "public func retire", "public func reset")
        self.assertIn("retired = true", retire)
        self.assertIn("editorID = UUID()", retire)
        self.assertIn("entries = []", retire)
        reset = section(IDENTITY, "public func reset", "private func hasCurrentOwner")
        self.assertLess(reset.index("retire()"), reset.index("Self.validate(slots)"))
        self.assertIn("guard currentOwner() == owner", reset)
        current = section(IDENTITY, "private func hasCurrentOwner", "private static func validate")
        self.assertIn("guard !retired", current)
        self.assertIn("guard currentOwner() == owner", current)
        self.assertIn("retire(); return false", current)
        self.assertIn("cannot detect an unobserved A -> B -> A transition", IDENTITY)

    def test_inventory_is_read_only_and_uses_supplied_story_uuids(self):
        self.assertIn("originalDraft = draft", SNAPSHOT)
        for raw in ["draft.questionImg", "draft.questionAudio", "draft.audioUrl", "options.text(letter, .image)",
                    "options.text(letter, .audio)", "raw: reference"]:
            self.assertIn(raw, SNAPSHOT)
        self.assertIn("if options.isSupported", SNAPSHOT)
        self.assertIn("if let loadedStoryBeats", SNAPSHOT)
        self.assertIn("Set(loadedStoryBeats.map(\\.id))", SNAPSHOT)
        self.assertIn(".storyBeatImage(beatID: beat.id)", SNAPSHOT)
        self.assertIn("Self.matches(loadedStoryBeats, stored: parsed)", SNAPSHOT)
        for mutator in ["setStory(", "setChoiceOptionMedia(", "JSONEncoder", "sourceTrim(reference)"]:
            self.assertNotIn(mutator, SNAPSHOT)

    def test_new_core_seams_cannot_access_media_transport_or_persistence(self):
        for source in [IDENTITY, SNAPSHOT]:
            for forbidden in ["URLSession", "FileManager", "UserDefaults", "AVFoundation", "PhotosUI",
                              "TemplateAuthoringLocalStore", "TemplateAuthoringAdapter", "ImageUploadJournal",
                              "RetainedImageUploader", "JSONEncoder", "write(to:"]:
                self.assertNotIn(forbidden, source)
        self.assertIn("@MainActor public final class TemplateAuthoringMediaIdentityScope", IDENTITY)

    def test_dormant_seams_are_not_referenced_by_central_ui(self):
        for path in (ROOT / "App").glob("*.swift"):
            source = path.read_text()
            self.assertNotIn("TemplateAuthoringMediaIdentityScope", source, str(path))
            self.assertNotIn("TemplateAuthoringMediaReferenceSnapshot", source, str(path))

    def test_authored_xctest_inventory_includes_historical_lifecycle_hazards(self):
        tests = (ROOT / "Tests/CoreTests/TemplateAuthoringMediaIdentityTests.swift").read_text()
        snapshot_tests = (ROOT / "Tests/CoreTests/TemplateAuthoringMediaReferenceSnapshotTests.swift").read_text()
        for name in ["testCancelInvalidatesOnlyItsSelectionAndLateCancelLeavesNewerSelection",
                     "testExplicitTopologyEventInvalidatesAnUnchangedMediaList",
                     "testEverySessionDimensionAndDraftIdentityInvalidatesLease",
                     "testExplicitRetirementFencesUnobservedAccountRoundTrip",
                     "testRealCoordinatorDiscardPreservesDraftIDSoHostMustResetMediaIncarnation"]:
            self.assertIn("func " + name, tests)
        for name in ["testReloadReallyMintsStoryUUIDsAndSnapshotSlotsAreNotDurable",
                     "testStoryUsesSuppliedLoadedUUIDsAndDistinctSlotsForDuplicateReferences",
                     "testUnsupportedStoryRemainsOpaqueAndCannotReceiveLoadedBeatTargets",
                     "testInventoryDoesNotChangeDraftEncodingOrExistingWirePayload"]:
            self.assertIn("func " + name, snapshot_tests)


if __name__ == "__main__":
    unittest.main()

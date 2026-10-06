"""Mode-specific creator starter source checks. These do not execute Apple UI."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT/path).read_text()

class ProjectEditStarterChecks(unittest.TestCase):
    def test_shared_creation_keeps_city_and_free_destinations_distinct(self):
        core = read('Core/ProjectEditStarterPolicy.swift')
        for token in ['case story, firstNode', 'product == .city || chapter.preserved["opening"] == .bool(true)',
                      'return hadChapters ? nil : .firstNode', 'chapter.blocks = []', 'chapter.schemaVersion = 1', 'chapter.required = 1']:
            self.assertIn(token, core)
        self.assertNotIn('chapter.description = "', core)
        ui = read('App/ProjectEditStarterPresentation.swift')
        self.assertIn('case .story:', ui); self.assertIn('ProjectEditChapterView(', ui)
        self.assertIn('case .firstNode:', ui); self.assertIn('ProjectEditNodeFields(node: controller.node(for: original))', ui)
        for forbidden in ['RoamRun', 'PlaySession', 'markComplete', 'issueCoupon', 'startLocation', 'URLSession', 'upload(']: self.assertNotIn(forbidden, core + ui)

    def test_just_created_identity_and_locked_mode_are_captured_before_destination(self):
        source = read('App/ProjectEditStarterController.swift')
        for token in ['guard let lease, model.isCurrentStarterLease(lease)', 'model.draft.chapters.append(chapter)',
                      'chapterID: chapter.id', 'hadChapters: hadChapters', 'baseline.draft.product == draft.product',
                      'baseline.draft.owner == draft.owner', 'baseRevision: Array(draft.baseRevision.utf8)',
                      'incarnation: editorIncarnation', 'structureRevision: structureRevision']:
            self.assertIn(token, source)
        host = read('App/ProjectEditView.swift')
        self.assertIn('let opening = model.captureStarterLease()', host)
        self.assertIn('starter.createChapter(lease: opening, name: name)', host)
        self.assertIn('oldValue.chapters.map(\\.id) != draft.chapters.map(\\.id)', host)
        self.assertIn('oldValue.product != draft.product', host)

    def test_old_dismissal_or_binding_does_not_reacquire_new_destination(self):
        source = read('App/ProjectEditStarterController.swift')
        self.assertIn('destination?.id == value.id && destination?.lease == value.lease', source)
        self.assertIn('guard self.isCurrentStarterChapter(value), next.id == value.chapterID', source)
        self.assertIn('model.invalidateStarterLease()', source)
        ui = read('App/ProjectEditStarterPresentation.swift')
        self.assertIn('let original = controller.destination', ui)
        self.assertIn('controller.close(original)', ui)
        self.assertNotIn('onDismiss:', ui)
        details = read('App/ProjectEditDetailForms.swift')
        self.assertIn('return model.starterChapter(starterLease)', details)
        self.assertIn('starterLease: starterLease', details)

    def test_temporary_node_only_commits_explicitly_when_valid_and_current(self):
        source = read('App/ProjectEditStarterController.swift')
        section = source.split('func finish(')[1].split('func close(')[0]
        self.assertIn('guard canFinish(value)', section)
        self.assertIn('firstIndex(where: { $0.id == value.chapterID })', section)
        self.assertIn('nodes.isEmpty', section); self.assertIn('nodes.append(candidate)', section)
        self.assertIn('if ProjectEditStarterPolicy.canAddFormalNode(candidate)', section)
        self.assertIn('ProjectEditPendingMaterials.saving(candidate, in: next)', section)
        self.assertIn('guard model.persistLocalChange(next, lease: value.lease)', section)
        self.assertNotIn('nodes.append', source.split('func finish(')[0])
        core = read('Core/ProjectEditStarterPolicy.swift')
        self.assertIn('node.hasUsableCoordinates', core); self.assertIn('node.nodeTime >= 0', core)
        close = source.split('func close(')[1].split('func retire')[0]
        self.assertNotIn('draft.chapters', close)
        self.assertIn('candidate = .init()', close)

    def test_capture_invalidates_on_real_model_lifecycle(self):
        model = read('App/ProjectEditView.swift')
        for token in ['func restore() { guard ownsVisit else { return }; cancelReview(); editorIncarnation = UUID()', 'func discard() { guard ownsVisit else { return }; cancelReview(); editorIncarnation = UUID()',
                      'guard ownsVisit else { return }; generation += 1; editorIncarnation = UUID()', 'editorIncarnation = UUID(); generation += 1',
                      'editorIncarnation = UUID(); draft = seed', 'starter.retire(); pending.retire(); model.leave()']:
            self.assertIn(token, model)
        fixtures = read('App/ProjectEditFixtureSupport.swift')
        self.assertTrue(fixtures.startswith('#if DEBUG')); self.assertIn('--project-edit-starter-probe', fixtures)
        self.assertIn('store.load(session: session, identity: identity, baseline: initial.draft)', fixtures)
        self.assertIn('service.submissions.count', fixtures)

    def test_opening_node_guard_is_at_mutation_boundary_and_actual_button_action(self):
        domain = read('Core/ProjectEditDraft.swift').split('public mutating func addNode(')[1].split('public mutating func removeNode')[0]
        self.assertIn('guard preserved["opening"] != .bool(true)', domain)
        ui = read('App/ProjectEditDetailForms.swift')
        self.assertIn('systemImage: "plus", action: addNode', ui)
        action = ui.split('func addNode()')[1].split('private func blockBinding')[0]
        self.assertIn('guard exists, model.fullEdit', action)
        self.assertIn('try current.addNode(product: model.draft.product)', action)
        tests = read('Tests/AppUnitTests/ProjectEditStarterControllerTests.swift')
        self.assertIn('let oldButtonAction = view.addNode', tests)
        self.assertIn('oldButtonAction()', tests)

    def test_bilingual_fragment_and_authoring_route_regressions(self):
        entries = json.loads(read('Resources/ProjectEditStarterLocalizations.fragment.json'))['strings']
        self.assertEqual(len(entries), 8)
        for entry in entries.values(): self.assertEqual(set(entry['localizations']), {'en','zh-Hans'})
        for path, count in [('Tests/CoreTests/ProjectEditStarterPolicyTests.swift',5), ('Tests/AppUnitTests/ProjectEditStarterControllerTests.swift',8), ('Tests/AppUITests/ProjectEditStarterFlowTests.swift',2)]:
            self.assertEqual(read(path).count('func test'), count)
        tests = read('Tests/AppUnitTests/ProjectEditStarterControllerTests.swift')
        for token in ['"modeABA"', '"deleteABA"', '"reorder"', 'XCTAssertTrue(service.submissions.isEmpty)', 'store.load(session:', 'binding.wrappedValue = chapter']:
            self.assertIn(token, tests)
        ui = read('Tests/AppUITests/ProjectEditFlowTests.swift')
        self.assertIn('XCTAssertFalse(addNode.isEnabled)', ui); self.assertIn('XCTAssertTrue(addNode.isEnabled)', ui)
        self.assertIn('let expectedStory = "A real opening story"', ui)

if __name__ == '__main__': unittest.main()

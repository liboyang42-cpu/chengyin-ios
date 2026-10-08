import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProjectChapterRemovalContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_real_chapter_delete_callback_opens_review_instead_of_mutating(self):
        view = self.read('App/ProjectEditView.swift')
        section = view.split('private func chapterStructure(')[1].split('private func chapterLabel(')[0]
        self.assertIn('let removalCapture = chapterRemoval.capture()', section)
        self.assertIn('.onDelete { chapterRemoval.open(offsets: $0, captured: removalCapture) }', section)
        self.assertNotIn('chapters.remove(', section)
        self.assertIn('ProjectChapterRemovalPresentation(model: model, controller: chapterRemoval)', view)
        self.assertIn('@StateObject private var chapterRemoval: ProjectChapterRemovalController', view)
        self.assertIn('chapterRemoval.retire(); starter.retire(); pending.retire(); model.leave()', view)
        self.assertIn('.deleteDisabled(removalCapture == nil)', section)
        self.assertIn('starter.createChapter(lease: opening, name: name)', section)

    def test_only_explicit_confirmation_can_persist_chapter_removal(self):
        host = self.read('App/ProjectChapterRemovalPresentation.swift')
        before, action = host.split('func confirm(_ value: Confirmation)')
        self.assertNotIn('persistLocalChange', before)
        action = action.split('func close(')[0]
        self.assertLess(action.index('isCurrent(value)'), action.index('ProjectChapterRemoval.removing'))
        self.assertLess(action.index('saving = true'), action.index('model.persistLocalChange'))
        self.assertIn('!saveUnconfirmed', action)
        self.assertIn('failedConfirmation = value', action)
        self.assertIn('model.coordinator.suspendLocalWritesAfterChapterRemoval(value.readback)', action)
        self.assertIn('Button("projectChapterRemoval.confirm", role: .destructive)', host)
        self.assertIn('.disabled(controller.saveUnconfirmed)', host)
        self.assertIn('ForEach(value.chapters)', host)
        self.assertIn('chapter.nodes.count', host)

    def test_owner_model_render_revision_and_identity_fences(self):
        host = self.read('App/ProjectChapterRemovalPresentation.swift')
        for token in ['value.controllerID == controllerID', 'value.generation == generation',
                      'model.isCurrentStarterLease(value.lease)', 'model.draftMutationRevision == value.revision',
                      'ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes',
                      'model.draft.chapters.map(\\.id) == value.chapterIDs',
                      'offsets.allSatisfy({ captured.chapterIDs.indices.contains($0) })',
                      'confirmation?.id == value.id', 'self.close(original)']:
            self.assertIn(token, host)
        self.assertIn('guard !saveUnconfirmed, let lease = model.captureStarterLease()', host)
        self.assertIn('guard !saving, !saveUnconfirmed, let captured', host)

    def test_core_removal_copies_unknown_siblings_and_never_rewrites_cross_chapter_rules(self):
        core = self.read('Core/ProjectChapterRemoval.swift')
        self.assertIn('var next = draft', core)
        self.assertIn('next.chapters.removeAll { selected.contains($0.id) }', core)
        self.assertIn('Set(available).count == available.count', core)
        self.assertIn('ids.allSatisfy({ available.contains($0) })', core)
        for forbidden in ['routeGraphJson', 'pendingMaterials =', '.preserved[', 'chapters = []', '/api/', 'URLSession']:
            self.assertNotIn(forbidden, core)

    def test_readback_capability_is_issued_for_current_coordinator_not_arbitrary_identity(self):
        core = self.read('Core/ProjectEditCoordinator.swift')
        scope = core.split('public struct ChapterRemovalReadback {')[1].split('/// Read-only eligibility')[0]
        for token in ['fileprivate let coordinator: ProjectEditCoordinator', 'fileprivate let identity: ProjectEditDraftIdentity',
                      'fileprivate let session: ProjectEditSession', 'fileprivate let visit: UUID',
                      'value.coordinator === self', 'currentSession() == value.session',
                      'identity == value.identity', 'editorVisit == value.visit',
                      'generation == value.generation', 'snapshot?.scope == .full']:
            self.assertIn(token, scope)
        readback = scope.split('public func inspectChapterRemoval(')[1]
        self.assertEqual(readback.count('chapterRemovalReadbackIsCurrent(value)'), 2)
        self.assertIn('store.load(session: value.session, identity: value.identity, baseline: baseline.draft)', readback)
        for forbidden in ['store.save(', 'store.remove(', 'activeIdentity(', 'restore =', 'messageKey =', 'confirm(']:
            self.assertNotIn(forbidden, readback)
        for case in ['original', 'removed', 'other', 'missing', 'unavailable', 'stale']:
            self.assertIn('.' + case, readback)

    def test_readback_never_acknowledges_or_retries_and_failure_remains_locked(self):
        host = self.read('App/ProjectChapterRemovalPresentation.swift')
        inspect = host.split('func inspect()')[1].split('func retire()')[0]
        for forbidden in ['saveUnconfirmed = false', 'model.draft =', 'persistLocalChange', 'load(force:', 'confirm(']:
            self.assertNotIn(forbidden, inspect)
        retire = host.split('func retire()')[1].split('func binding(')[0]
        self.assertNotIn('saveUnconfirmed = false', retire)
        self.assertIn('if !saveUnconfirmed { generation += 1 }', host)
        self.assertIn('ProjectChapterRemovalStatus(controller: chapterRemoval)', self.read('App/ProjectEditView.swift'))

    def test_unconfirmed_save_freezes_all_local_write_entrypoints_for_bound_owner_and_identity(self):
        core = self.read('Core/ProjectEditCoordinator.swift')
        for signature in ['public func copyForMode(', 'public func discardLocalDraft()',
                          '@discardableResult public func saveLocal(', 'public func canReplaceExistingStoryDraft(',
                          'public func prepare(', 'public func confirm(']:
            body = core.split(signature)[1].split('\n    }', 1)[0]
            self.assertIn('guard !hasUnconfirmedChapterRemoval, !isBusy, !isLocked', body)
        self.assertIn('unconfirmedChapterRemovalDrafts.contains(.init(ownerKey: session.ownerKey, bucket: identity.bucket))', core)
        self.assertIn('unconfirmedChapterRemovalDrafts.insert(.init(ownerKey: value.session.ownerKey, bucket: value.identity.bucket))', core)
        self.assertNotIn('unconfirmedChapterRemovalDrafts.remove', core)
        model = self.read('App/ProjectEditView.swift')
        self.assertIn('var canEdit: Bool { ownsVisit && !coordinator.hasUnconfirmedChapterRemoval', model)
        self.assertIn('func saveLocal() { guard canSaveLocal else { return }', model)
        self.assertIn('guard isCurrentStarterLease(lease)', model)

    def test_bilingual_fragment_covers_every_new_user_string(self):
        host = self.read('App/ProjectChapterRemovalPresentation.swift')
        host = re.sub(r'\.accessibilityIdentifier\("[^"]+"\)', '', host)
        keys = set(re.findall(r'"(projectChapterRemoval\.[A-Za-z.]+)"', host))
        fragment = json.loads(self.read('Resources/ProjectChapterRemovalLocalizations.fragment.json'))
        self.assertEqual(fragment['sourceLanguage'], 'en')
        self.assertEqual(keys, set(fragment['strings']))
        for entry in fragment['strings'].values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for value in entry['localizations'].values():
                self.assertTrue(value['stringUnit']['value'].strip())

    def test_authored_lifecycle_regressions_include_real_storage_and_production_writes_stay_off(self):
        unit = self.read('Tests/AppUnitTests/ProjectChapterRemovalTests.swift')
        domain = self.read('Tests/CoreTests/ProjectChapterRemovalTests.swift')
        self.assertEqual(domain.count('func test'), 6)
        self.assertEqual(unit.count('func test'), 18)
        for token in ['offset in [1, 2]', 'storage.afterRead = { owner.session = nil }',
                      'controller.confirm(confirmation); controller.confirm(confirmation)',
                      'scope: .whitelist', 'fresh.restore()', 'controller.canInspect',
                      'store.activeIdentity(', 'replacement.coordinator.inspectChapterRemoval',
                      'model.coordinator.pending?.operationID', '"contentABA"']:
            self.assertIn(token, unit)
        for forbidden in ['URLSession', 'OperationEndpointApproval', 'UserDefaults', 'coordinator.confirm(']:
            self.assertNotIn(forbidden, self.read('App/ProjectChapterRemovalPresentation.swift'))


if __name__ == '__main__':
    unittest.main()

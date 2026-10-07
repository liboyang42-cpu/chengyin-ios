"""Native structural evidence only; does not execute Swift, Apple UI, or backend services."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ProjectStoryTemplateSelectionContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_reader_is_personal_drafts_only_and_never_a_mutation_transport(self):
        source = self.read('Core/ProjectStoryTemplateClient.swift')
        for text in ['"draft_status": "0"', '"scope": ""', '"pageNum": String(page)', '"pageSize": String(ProjectStoryTemplatePage.pageSize)', 'case .detail(let id): return ["id": String(id.rawValue)]', 'approval: OperationEndpointApproval? = nil', 'currentCapability: @escaping (String) -> Bool = { _ in false }']:
            self.assertIn(text, source)
        for text in ['URLSession', 'is_quote', 'api/template/draft"', 'api/template/publish', 'api/template/homeData', 'MERCHANT']:
            self.assertNotIn(text, source)

    def test_context_fence_brackets_success_and_failure(self):
        source = self.read('Core/ProjectStoryTemplateClient.swift')
        self.assertGreaterEqual(source.count('try requireCurrent(credentials)'), 3)
        self.assertIn('currentCredentials() == credentials', source)
        self.assertIn('try Task.checkCancellation()', source)
        self.assertIn('data.count <= 1024 * 1024', source)

    def test_domain_rejects_owner_published_arrival_and_ambiguous_album(self):
        source = self.read('Core/ProjectStoryTemplateSelection.swift')
        for text in ['fields["memberId"]?.integer == accountID', 'fields["draftStatus"] == .number(0)', 'fields["delFlag"] == .number(0)', '[0, 1, 2, 3, 6, 7].contains(method)', 'config["schemaVersion"] == .number(1)', 'enabled == .bool(true) || enabled == .bool(false)', 'Set(album.keys).isSubset(of: ["enabled", "images"])', 'Set(image.keys).isSubset(of: ["url", "line"])', 'advanced.issues.isEmpty', '$0.key != "album" && $0.value.object?["enabled"] == .bool(true)']:
            self.assertIn(text, source)

    def test_album_checks_intersection_and_preserves_source_in_snapshot(self):
        source = self.read('Core/ProjectStoryTemplateSelection.swift')
        for text in ['(1...6).contains(images.count)', 'row.title.utf16.count <= 20', 'url.utf16.count <= 500', 'line.utf16.count <= 40', 'private let exactSource: Data', 'lhs.exactSource == rhs.exactSource', 'fields.removeValue(forKey: "line")', 'content = .album(images)']:
            self.assertIn(text, source)
        self.assertNotIn('prefix(6)', source)

    def test_target_reuses_exact_gap_and_keeps_pending_untouched(self):
        source = self.read('Core/ProjectStoryTemplateSelection.swift')
        for text in ['public let gap: ProjectStoryMediaGap', 'draft.product == .city, draft.owner == .personal', 'Set(blockIDs).count == blockIDs.count', 'Set(nodeIDs).count == nodeIDs.count', 'Set(references) == Set(chapter.nodes.map(\\.id))', 'gap.inserting(block, into: draft', 'created.templateID = selected.row.id.rawValue', 'created.longitude = ""; created.latitude = ""', 'value.sourceFields = ["locationRequired": .bool(false)]', 'value.sourceFields = ["title": .string(selected.row.title), "images": .array(images)]']:
            self.assertIn(text, source)
        self.assertNotIn('next.pendingMaterials =', source)
        self.assertNotIn('next.pendingMaterials?.remove', source)

    def test_opening_and_ending_do_not_gain_location_nodes(self):
        source = self.read('Core/ProjectStoryTemplateSelection.swift')
        for text in ['index == 0 && chapter.preserved["recruitEnabled"]?.integer != 1', 'chapter.nodes.isEmpty', 'ProjectEditRichStoryContract.validateCondition(condition, ending: true)', 'chapter.nodes.allSatisfy({ $0.longitude.isEmpty && $0.latitude.isEmpty', 'case .gameplay:\n            guard let chapter', 'chapter.preserved["ending"] == nil || chapter.preserved["ending"] == .null']:
            self.assertIn(text, source)
        # Existing formal-node / coordinate validation is retained verbatim.
        prior = self.read('Core/ProjectEditDraft.swift')
        self.assertIn('guard preserved["opening"] != .bool(true), preserved["ending"]?.object == nil', prior)
        self.assertIn('storyGame ? node.longitude.isEmpty && node.latitude.isEmpty && (node.templateID ?? 0) > 0 : node.hasUsableCoordinates', prior)

    def test_presentation_captures_owner_editor_and_source_aba(self):
        source = self.read('App/ProjectStoryTemplatePresentation.swift')
        for text in ['let sourceID: UUID', 'source.identity == original.sourceID', 'ObjectIdentifier(source) == ObjectIdentifier(original.source)', 'editor.draftMutationRevision == original.draftRevision', 'editor.isCurrentStarterLease(original.lease)', 'host.allows(editor: editor', 'target == original.target', 'requestID == stamp && owns(original)']:
            self.assertIn(text, source)

    def test_explicit_adoption_rereads_before_single_local_save(self):
        source = self.read('App/ProjectStoryTemplatePresentation.swift')
        apply = source.split('@discardableResult func apply(', 1)[1].split('private func accepts', 1)[0]
        for text in ['state = .applying', 'original.source.detail(', 'current == selected.source', 'self.editor.persistExistingStoryChange(selected.draft, lease: original.lease)', 'self.state = .saveFailed', 'self.close(original)']:
            self.assertIn(text, apply)
        self.assertLess(apply.index('state = .applying'), apply.index('let task = Task'))
        self.assertEqual(apply.count('persistExistingStoryChange('), 1)
        self.assertNotIn('submit(', source)

    def test_cancel_return_and_immutable_preview_do_not_edit(self):
        source = self.read('App/ProjectStoryTemplatePresentation.swift')
        self.assertIn('let draft: ProjectEditDraft', source)
        for name in ['func back(', 'func close(']:
            body = source.split(name, 1)[1].split('\n    }', 1)[0]
            self.assertNotIn('persistLocalChange', body)
        view = self.read('App/ProjectStoryTemplateView.swift')
        self.assertIn('ProjectStoryTemplatePreview(source: review.source)', view)
        self.assertIn('controller.apply(review, original: original)', view)
        for text in ['AsyncImage', 'URLSession', 'coordinator.prepare', 'submit(']: self.assertNotIn(text, view)

    def test_real_chapter_controls_mount_first_middle_end_sheet(self):
        source = self.read('App/ProjectEditDetailForms.swift')
        for text in ['storyTemplates.capture(chapterID: chapterID, before: nil)', 'storyTemplates.capture(chapterID: chapterID, before: blockID)', 'projectStoryTemplate.insertBefore.', 'projectStoryTemplate.add', '.sheet(item: storyTemplates.binding(templateOpening))', 'ProjectStoryTemplateView(controller: storyTemplates, original: original)', 'if let templateOpening { storyTemplates.close(templateOpening) }']:
            self.assertIn(text, source)

    def test_production_dependency_defaults_nil_and_central_issuance_is_absent(self):
        source = self.read('Core/ProjectEditCoordinator.swift')
        self.assertIn('storyTemplateSource: (any ProjectStoryTemplateReading)? = nil', source)
        self.assertIn('storyTemplateSource: storyTemplateSource, currentSession:', source)
        for path in ['App/AppSession.swift', 'App/AppCompositionRoot.swift']:
            self.assertNotIn('ProjectStoryTemplate', self.read(path))

    def test_inner_advanced_document_has_bounded_lossless_preflight(self):
        source = self.read('Core/ProjectStoryTemplateSelection.swift')
        self.assertIn('raw.utf8.count <= 262_144', source)
        self.assertLess(source.index('ApprovedTopicReleaseWire.envelope(Data(raw.utf8))'), source.index('TemplateAdvancedDraft(raw: raw)'))
        shared = self.read('Core/ApprovedTopicReleaseDomain.swift')
        for text in ['depth <= 32', 'tokens <= 100_000', 'atomBytes <= 128', 'ContentDraftJSON.parse(text)']:
            self.assertIn(text, shared)
        tests = self.read('Tests/CoreTests/ProjectStoryTemplateSelectionTests.swift')
        for name in ['testInnerAdvancedJSONRejectsDuplicateKeysBeforeBothTypedDecoders', 'testInnerAdvancedJSONRejectsEscapedAliasesButAcceptsOneEscapedKey', 'testInnerAdvancedJSONHasBoundedSizeDepthStringAndAtomPreflight']:
            self.assertIn(name, tests)

    def test_chooser_existing_preimage_has_single_write_without_pointer_or_fallback(self):
        store = self.read('Core/ProjectEditLocalStore.swift')
        replace = store.split('public func replaceExistingStoryDraft(', 1)[1].split('private func existingStoryPreimage', 1)[0]
        self.assertEqual(replace.count('storage.write('), 1)
        self.assertNotIn('active:', replace); self.assertNotIn('try save(', replace)
        guard = store.split('private func existingStoryPreimage(', 1)[1].split('public func activeIdentity', 1)[0]
        for text in ['pointer == identity', 'ApprovedTopicReleaseWire.envelope(pointerData)', 'stored.accountID == session.accountID', 'stored.namespace == session.storageNamespace', 'originalDraft = raw["draft"]', 'ContentDraftJSON.parse(sourceText)']:
            self.assertIn(text, guard)
        self.assertLess(guard.index('ApprovedTopicReleaseWire.envelope(data)'), guard.index('JSONDecoder().decode(ProjectEditEnvelope.self'))
        opening = self.read('App/ProjectStoryTemplatePresentation.swift').split('@discardableResult func open(', 1)[1].split('@discardableResult func refresh', 1)[0]
        self.assertLess(opening.index('editor.canReplaceExistingStoryDraft()'), opening.index('load(original, page: 1)'))
        self.assertIn('state = .saveRequired; return nil', opening)
        self.assertIn('projectStoryTemplate.saveRequired', self.read('App/ProjectEditDetailForms.swift'))

    def test_all_new_ui_copy_is_bilingual_and_matches_catalog(self):
        fragment = json.loads(self.read('docs/project-story-template-localizations.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 17)
        for key, value in fragment.items():
            self.assertEqual(value, catalog[key])
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'])

if __name__ == '__main__': unittest.main()

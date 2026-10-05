"""Supplementary source fences; behavioral Swift tests require the Apple toolchain."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text()

class TemplateMetadataSelectorChecks(unittest.TestCase):
    def test_route_is_narrow_and_existing_authority_is_retained(self):
        core = read('Core/TemplateMetadata.swift')
        composition = read('App/AppCompositionRoot.swift')
        self.assertIn('canonical.httpBody == body', core)
        self.assertIn('request.httpBodyStream == nil', core)
        self.assertIn('Data(url.absoluteString.utf8) == Data(expected.absoluteString.utf8)', core)
        branch = composition.split('} else if url == api.baseURL.appendingPathComponent("api/common/dict") {')[1].split('} else if')[0]
        self.assertIn('deployment.reads.contains(.homeAndSearch)', branch)
        self.assertIn('TemplateMetadataReadRoute(request: request, baseURL: api.baseURL)', branch)
        broad = composition.split('let reads = ')[1].split('\n')[0]
        self.assertNotIn('common/dict', broad)
    def test_metadata_unauthorized_expiration_is_deferred_to_current_sheet(self):
        session = read('App/AppSession.swift').split('private func templateMetadataRequest<Value>')[1].split('func discoveryTemplateHome')[0]
        self.assertIn('readDiscovery(expiresSession: false, operation)', session)
        self.assertIn('viewerRevision == self.compositionViewerRevision', session)
        editor = read('App/TemplateAuthoringMetadataSelectors.swift')
        self.assertIn('guard accepts(stamp) else { return }\n        if case APIError.unauthorized', editor)
        self.assertIn('stamp == generation && canEdit && !Task.isCancelled', editor)
        self.assertIn('originalDraft == model.draft', editor)
        self.assertIn('readerIdentity == reader?.discoveryPresentationIdentity', editor)
    def test_only_explicit_selection_changes_draft_and_does_not_set_primary_category(self):
        editor = read('App/TemplateAuthoringMetadataSelectors.swift')
        load = editor.split('func load() async')[1].split('private func accepts')[0]
        self.assertNotIn('model.draft.', load); self.assertNotIn('model.changed()', load)
        self.assertIn('model.draft.players = option.value', editor)
        self.assertIn('model.draft.duration = minutes', editor)
        self.assertIn('if selection.hasChanges', editor)
        self.assertIn('model.draft.activityCategoryids = selection.savedValue', editor)
        self.assertNotIn('model.draft.categoryId =', editor)
        self.assertNotIn('.fallback', editor)
    def test_category_projection_retains_exact_bytes_and_has_no_limit(self):
        source = read('Core/TemplateMetadataCategorySelection.swift')
        self.assertIn('guard isSupported, hasChanges else { return original }', source)
        self.assertIn('selectedIDs.append(id)', source)
        self.assertIn('replaceUnsupportedSelection()', source)
        for forbidden in ['prefix(', 'maximum', 'limit', 'sorted(']: self.assertNotIn(forbidden, source)
        bridge = read('App/AppSession.swift').split('func templateMetadataCategoriesRequest()')[1].split('// Only')[0]
        self.assertIn('categories(type: 4, token: $1)', bridge)
    def test_ui_is_mounted_in_production_and_fixture_reads_are_separate(self):
        view = read('App/TemplateAuthoringView.swift')
        self.assertIn('TemplateAuthoringMetadataFields(model: model, reader: metadataReader)', view)
        for key in ['players', 'duration', 'activityCategoryids']:
            self.assertNotIn('TemplateAuthoringField("' + key + '"', view)
        self.assertIn('metadataReader: session', read('App/TemplateAuthoringLaunchView.swift'))
        self.assertIn('metadataReader: reader', read('App/DiscoveryTemplateDetailView.swift'))
        fixture = read('App/TemplateAuthoringFixtureSupport.swift')
        self.assertIn('metadataReader = DiscoveryFixtureReader(metadataScenario: metadataScenario)', fixture)
        self.assertIn('requestCount: transport.requests.count', fixture)
    def test_localization_fragment_is_bilingual_code_data_only(self):
        values = json.loads(read('tools/template_metadata_localizations.json'))
        self.assertEqual(len(values), 12)
        for key, value in values.items():
            self.assertTrue(key.startswith('templateMetadata.'))
            self.assertEqual(set(value), {'en', 'zh-Hans'})
            self.assertTrue(all(isinstance(text, str) and text for text in value.values()))
    def test_real_swift_tests_cover_construction_decoding_dispatch_and_lifecycle(self):
        core = read('Tests/CoreTests/TemplateMetadataTests.swift')
        wire = read('Tests/AppUnitTests/TemplateMetadataReadCompositionTests.swift')
        life = read('Tests/AppUnitTests/TemplateMetadataSelectorLifecycleTests.swift')
        for text in ['service(wire).templateMetadataDictionary', 'request.httpBody, canonical.httpBody', 'testEveryRowRequiresBothStrictStrings']:
            self.assertIn(text, core)
        for text in ['transport.send(request)', 'wire.requests.count', 'testSessionRoleABA', 'testExtraDuplicateFileParts']:
            self.assertIn(text, wire)
        for text in ['withCheckedThrowingContinuation', 'testNewestLoadWins', 'testLateCategory401AfterDiscard', 'testCategoryNoopSaveCancel']:
            self.assertIn(text, life)

if __name__ == '__main__':
    unittest.main()

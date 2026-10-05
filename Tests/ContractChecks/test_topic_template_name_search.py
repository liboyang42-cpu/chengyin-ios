"""Native wiring guards only; Swift and UI execution require Apple tooling."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TopicTemplateNameSearchContracts(unittest.TestCase):
    def test_local_name_only_literal_search_has_no_transport_or_cached_rows(self):
        core = (ROOT / 'Core/DiscoveryContracts.swift').read_text()
        search = core.split('public struct DiscoveryTopicTemplateNameSearch:', 1)[1].split('public struct DiscoveryTemplateHome:', 1)[0]
        self.assertIn('keyword = text.trimmingCharacters(in: whitespace)', search)
        self.assertIn('let needle = keyword.lowercased()', search)
        self.assertIn('$0.name.lowercased().range(of: needle, options: .literal)', search)
        self.assertIn('guard isActive else { return rows }', search)
        for forbidden in ['subtitle', 'localizedCaseInsensitiveContains', 'URLSession', 'token', 'sorted(', 'Set<', 'previewOnly ==']:
            self.assertNotIn(forbidden, search)

    def test_name_filter_precedes_category_priority_and_game_state_stays_independent(self):
        view = (ROOT / 'App/DiscoveryTemplateBrowserView.swift').read_text()
        shelf = view.split('@ViewBuilder private var topicShelf:', 1)[1].split('@ViewBuilder private var gameShelf:', 1)[0]
        self.assertIn('let filtered = appliedTopicSearch.filter(rows)', shelf)
        self.assertIn('let matching = filtered.filter { $0.matchesCategory(categoryID) }', shelf)
        self.assertIn('let other = filtered.filter { !$0.matchesCategory(categoryID) }', shelf)
        self.assertIn('if rows.isEmpty', shelf)
        self.assertIn('if filtered.isEmpty', shelf)
        self.assertNotIn('appliedKeyword =', shelf)
        self.assertNotIn('pack =', shelf)
        apply = view.split('private func applyTopicSearch()', 1)[1].split('private func applySearch()', 1)[0]
        self.assertNotIn('load', apply.lower())
        query = view.split('private struct Query:', 1)[1].split('init(reader:', 1)[0]
        self.assertNotIn('topicKeyword', query)
        self.assertNotIn('appliedTopicSearch', query)
        self.assertIn('let requestedKeyword = appliedKeyword', view)

    def test_unchanged_request_authority_and_stateful_detail_identity_are_preserved(self):
        view = (ROOT / 'App/DiscoveryTemplateBrowserView.swift').read_text()
        self.assertIn('reader.publicTopicTemplateCatalogRequest()', view)
        self.assertIn('topics.load(onUnauthorized: request.onUnauthorized, request.read)', view)
        self.assertIn('DiscoveryTopicTemplatePreview(coordinator: reader.publicTopicTemplateCoordinator(id: item.id))\n                            .id(item.id)', view)
        service = (ROOT / 'Core/DiscoveryService.swift').read_text()
        read = service.split('public func topicTemplates(', 1)[1].split('public func publicTopicTemplate(', 1)[0]
        self.assertIn('fields: nil', read)
        for forbidden in ['keyword', 'pageNum', 'pageSize']:
            self.assertNotIn(forbidden, read)
        self.assertIn('authoringFactory(item)', (ROOT / 'App/DiscoveryTemplateDetailView.swift').read_text())
        self.assertNotIn('authoringFactory(item)', view.split('private func topicSection', 1)[1].split('private func gameSection', 1)[0])

    def test_bilingual_scope_and_authored_behavior_inventory(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['discovery.topicNameSearch', 'discovery.topicNameSearchScope', 'discovery.clearTopicNameSearch']:
            for lang in ['en', 'zh-Hans']:
                self.assertEqual(catalog[key]['localizations'][lang]['stringUnit']['state'], 'translated')
        self.assertIn('loaded here', catalog['discovery.topicNameSearchScope']['localizations']['en']['stringUnit']['value'])
        core = (ROOT / 'Tests/CoreTests/DiscoveryContractTests.swift').read_text()
        for name in ['TrimsAndUsesCaseInsensitiveNameSubstring', 'IgnoresSubtitleAndUnrelatedFields',
                     'PreservesSourceOrderCategoryPriorityAndPreviewFlags', 'IsLiteralWithoutAccentOrWidthFolding',
                     'UsesMiniTrimWhitespaceIncludingBOM', 'ProjectsOnlyCurrentRowsAndDoesNotCacheMatches']:
            self.assertIn('func testTopicNameSearch' + name, core)
        app = (ROOT / 'Tests/AppUnitTests/PublicTemplateCompositionTests.swift').read_text()
        self.assertIn('func testLocalTopicNameSearchUsesReloadedCatalogWithoutChangingWireShape', app)
        self.assertIn('func testLocalTopicNameSearchCannotRestoreSupersededCatalogResults', app)
        ui = ROOT / 'Tests/AppUITests/TopicTemplateNameSearchFlowTests.swift'
        self.assertEqual(ui.read_text().count('    func test'), 3)
        self.assertIn(str(ui.relative_to(ROOT)), (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text())


if __name__ == '__main__':
    unittest.main()

"""w2-07: source guards for mini-program topic detail parity (pages/topic/index)."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class W207TopicParity(unittest.TestCase):
    def test_existing_identifiers_and_read_call_are_kept(self):
        view = read('App/TopicDetailView.swift')
        for exact in ['.accessibilityIdentifier("topic.chapter.\\(chapter.id)")', 'accessibilityIdentifier("topic.lockedChapters")',
                      'accessibilityIdentifier("topic.detail.content")', 'accessibilityIdentifier("contextSelfPlay.open")',
                      'try await reader.topicDetail(id: id)', 'TopicXcxTabs(proxy: proxy)', '.id(TopicXcxTab.nodes.anchor)',
                      'TopicXcxRouteSection(topic: value).id(TopicXcxTab.route.anchor)']:
            self.assertIn(exact, view)
        self.assertIn('api/topic/info-to-user', read('Core/TopicService.swift'))

    def test_records_are_read_only_and_session_scoped(self):
        service = read('Core/TopicService.swift')
        for exact in ['"api/play/theme/history"', '"api/play/theme/card"', 'URLQueryItem(name: "limit", value: String(Self.themeHistoryLimit))']:
            self.assertIn(exact, service)
        self.assertNotIn('api/play/theme/replay', service + read('App/TopicThemeRecordsView.swift'))
        self.assertIn('TopicSessionReader: TopicReading, TopicThemeRecordsReading', read('Core/TopicReading.swift'))
        self.assertIn('if let records = reader as? any TopicThemeRecordsReading', read('App/TopicDetailView.swift'))

    def test_second_pass_sections_are_wired(self):
        view = read('App/TopicDetailView.swift')
        for exact in ['TopicXcxSessionChip(startDate: activity.startDate)', 'TopicXcxTemplatesSection(templates: TopicXcxFacts.nodeTemplates(value))',
                      'TopicXcxNodeFootView(node: node)', 'NativeMediaGalleryEntry(sources: covers']:
            self.assertIn(exact, view)

    def test_action_bar_never_dispatches(self):
        bar = read('App/TopicXcxSections.swift')
        self.assertNotRegex(bar, r'URLSession|httpMethod|registration/create|requestPayment')
        self.assertIn('.disabled(!topic.canOfferPurchase)', bar)

    def test_source_copy(self):
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        zh = lambda key: catalog[key]['localizations']['zh-Hans']['stringUnit']['value']
        for key, value in {'topicXcx.tab.details': '详情', 'topicXcx.tab.nodes': '路线节点', 'topicXcx.tab.route': '路线',
                           'topicXcx.reviews.emptyTitle': '还没有人评价过这条路线', 'topicXcx.cta.signUp': '立即报名',
                           'topicXcx.cta.locked.1': '招募中 · 未开售', 'topicXcx.cta.locked.2': '定价中 · 未开售',
                           'topicXcx.cta.locked.7': '立项待审 · 未开售', 'topicXcx.paywall.unlock': '立即解锁'}.items():
            self.assertEqual(zh(key), value, key)


if __name__ == '__main__':
    unittest.main()

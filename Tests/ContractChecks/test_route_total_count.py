"""Native presentation contracts; these do not replace Apple compilation/UI tests."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class RouteTotalCountContracts(unittest.TestCase):
    def test_card_and_detail_use_only_authoritative_optional_total(self):
        for path, expression in [('App/TopicBrowserView.swift', 'item.locationCount'), ('App/TopicDetailView.swift', 'value.locationCount'), ('App/HomeFeedView.swift', 'topic.locationCount'), ('App/AccountCollectionFavoritesView.swift', 'topic.locationCount')]:
            source = (ROOT / path).read_text()
            self.assertIn('TopicTotalStops(count: ' + expression, source)
            self.assertNotIn('locationCount > 0', source)
        view = (ROOT / 'App/TopicComponents.swift').read_text()
        self.assertIn('if let count { Text(verbatim: String(count))', view)
        self.assertIn('Text("topic.countUnknown")', view)
        self.assertIn('LabeledContent("topic.visibleChapterStops", value: String(chapter.nodes.count))', (ROOT / 'App/TopicDetailView.swift').read_text())

    def test_decoders_do_not_invent_zero_or_use_visible_nodes(self):
        for path in ['Core/TopicContracts.swift']:
            source = (ROOT / path).read_text()
            for line in source.splitlines():
                if 'locationCount =' in line:
                    self.assertNotIn('?? 0', line)
                    self.assertNotIn('nodes', line)
        self.assertIn('public let locationCount: Int?', (ROOT / 'Core/TopicContracts.swift').read_text())

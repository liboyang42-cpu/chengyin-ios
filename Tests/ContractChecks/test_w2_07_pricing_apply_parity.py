"""w2-07: source guards for topic pricing / partner and merchantapply parity."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class W207PricingApplyParity(unittest.TestCase):
    def test_pricing_keeps_dormant_review_and_identifiers(self):
        view = read('App/PublisherLifecycleViews.swift')
        for exact in ['accessibilityIdentifier("publisher.subtype")', 'accessibilityIdentifier("publisher.preview")',
                      'accessibilityIdentifier("publisher.finalPrice")', 'accessibilityIdentifier("publisher.reviewPrice")',
                      'accessibilityIdentifier("publisher.confirmPrice")', 'coordinator.confirm(review, consequentialApproval: true)',
                      'TopicPricingXcx.sliderMax(floor: preview.minimum, reference: preview.reference)', '"确认终价并提交开售审核"',
                      'preview.canConfirm == false', '"合作链接已失效"', '"开售即冻结"']:
            self.assertIn(exact, view)
        self.assertIn('"api/topic/pricing/preview"', read('Core/PublisherLifecycleHTTP.swift'))
        self.assertIn('public func partnerName(type: String, id: Int) async throws -> String', read('Core/PublisherLifecycleHTTP.swift'))
        self.assertIn('try? await client.partnerName(type: row.type, id: row.partnerID), generation == stamp', view)

    def test_topic_owner_pricing_entry_is_injected(self):
        self.assertIn(r'.environment(\.topicPricingDestination, session.publisherLifecycleContext', read('App/SessionTopicBrowserView.swift'))

    def test_merchant_apply_create_sends_source_dates(self):
        commands = read('Core/MerchantContentCommands.swift')
        self.assertIn('f["startDate"] = .string(range.start + " 00:00:00"); f["endDate"] = .string(range.end + " 23:59:59")', commands)
        editor = read('App/MerchantContentEditor.swift')
        self.assertIn('if case .registrationCreate = kind { applyDateSection }', editor)
        self.assertIn('MerchantApplyXcx.firstMissing(', editor)
        self.assertIn('MerchantApplyXcx.editBlock(status: s.value["status"].integer', editor)


if __name__ == '__main__':
    unittest.main()

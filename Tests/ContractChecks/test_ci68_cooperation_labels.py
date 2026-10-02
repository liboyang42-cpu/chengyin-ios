from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CooperationReviewAXTests(unittest.TestCase):
    def test_review_values_bind_exact_field_and_complete_localized_or_wire_value(self):
        s = (ROOT / 'Tests/AppUITests/CooperationFlowUITests.swift').read_text()
        for token in ['identifier == %@ AND label IN %@', '"coopflow.review.field." + field',
                      'reviewValue("Synthetic club", field: "toId"', '"Club ID 103" : "俱乐部 ID 103"',
                      '"Traffic cooperation" : "引流合作"', 'reviewValue("0", field: "shareMode"',
                      'reviewValue("MERCHANT", field: "scope"', 'XCTAssertFalse(submit.isEnabled)',
                      'coopflow.review.field.originApplyId', 'coopflow.review.field.topicId']:
            self.assertIn(token, s)
        self.assertNotIn('label CONTAINS', s)

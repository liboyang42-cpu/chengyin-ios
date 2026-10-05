"""Source guards only; Swift decoder and UI regressions run in hosted Apple CI."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PublicTemplateTotalContracts(unittest.TestCase):
    def test_shelf_and_detail_share_strict_nullable_decoder(self):
        for file in ['Core/DiscoveryContracts.swift', 'Core/PublicTopicTemplateDetail.swift']:
            text = (ROOT / file).read_text()
            self.assertIn('locationCount = try PublicTemplateRouteCount.decode(from: c, forKey: .locationCount)', text)
        decoder = (ROOT / 'Core/PublicTemplateRouteCount.swift').read_text()
        self.assertIn('decodeIfPresent(Int.self', decoder)
        self.assertNotIn('?? 0', decoder)
        self.assertNotIn('nodes', decoder.split('enum PublicTemplateRouteCount', 1)[1])

    def test_shelf_and_detail_share_total_presentation_without_zero_gate(self):
        for file in ['App/DiscoveryComponents.swift', 'App/DiscoveryTemplateDetailView.swift']:
            text = (ROOT / file).read_text()
            self.assertIn('TopicTotalStops(count: item.locationCount', text)
            self.assertNotIn('locationCount > 0', text)

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class FeaturedPlayOccurrenceQueryChecks(unittest.TestCase):
    def test_exact_fixture_metadata_disambiguates_repeated_template_id(self):
        source = (ROOT / 'Tests/AppUITests/PublicPlayTemplatePresentationFlowTests.swift').read_text()
        helper = source.split('private func revealedPlayCard()', 1)[1].split('private func expect(', 1)[0]
        self.assertIn('Notice the city, Single-location play, Players, 2–6, Duration, 45 min', helper)
        self.assertIn('Notice the city、单节点玩法、建议人数、2–6、时长、45 分钟', helper)
        self.assertIn('matching(identifier: "discovery.play.701")', helper)
        self.assertIn('.matching(NSPredicate(format: "label == %@", caption))', helper)
        self.assertIn('if query.count == 1', helper)
        self.assertNotIn('firstMatch', helper)
        self.assertIn('query.count > 1', helper)

    def test_only_maximum_text_exact_link_can_use_clipped_safe_region(self):
        source = (ROOT / 'Tests/AppUITests/PublicPlayTemplatePresentationFlowTests.swift').read_text()
        helper = source.split('private func revealedPlayCard()', 1)[1].split('private func expect(', 1)[0]
        for guard in ['button.isEnabled && button.isHittable', 'visible.width >= 44 && visible.height >= 44',
                      'frame.minX >= bounds.minX && frame.maxX <= bounds.maxX',
                      'frame.height > bounds.height || bounds.contains(frame) || maximumText',
                      'app.launchArguments.contains("--uitesting-max-text")',
                      'bar.frame.maxY + 4', 'keyboard.frame.minY - 4']:
            self.assertIn(guard, helper)
        self.assertIn('visible.midX - frame.minX', source)
        self.assertIn('visible.midY - frame.minY', source)

"""Source-level integration guards, not a Swift syntax or UI test."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class HomeCompositionTests(unittest.TestCase):
    def test_square_entry_is_not_duplicated_into_template_modal(self):
        source=(ROOT/'App/SessionHomeFeedView.swift').read_text()
        self.assertEqual(source.count('accessibilityIdentifier("homeFeed.openSquare")'),1)
        self.assertEqual(source.count('accessibilityIdentifier("homeFeed.openTemplates")'),1)
        template_modal=source.split('.sheet(isPresented:$showsTemplates)',1)[1]
        self.assertNotIn('showsSquare=true',template_modal)
        self.assertIn('placement:.cancellationAction',template_modal)
        self.assertIn('showsTemplates=false',template_modal)

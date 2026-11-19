"""motion-1119 sheet/press follow-ups from docs/motion-audit-1118.md section 4. Offline source guard only."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(name):
    return (ROOT / 'App' / name).read_text()


class NativeMotion1119Sheets(unittest.TestCase):
    def test_roam_detail_sheet_uses_place_card_detents(self):
        text = source('RoamBrowserView.swift')
        sheet = text.split('.sheet(item: $selected) { item in', 1)[1].split('.toolbar {', 1)[0]
        self.assertIn('.presentationDetents([.medium, .large])', sheet)
        self.assertIn('.presentationDragIndicator(.visible)', sheet)

    def test_club_post_body_is_native_card_button_with_animated_toggle(self):
        body = source('ClubPostDiscussion.swift').split('struct ClubPostDiscussionBody', 1)[1].split('struct ClubPostDiscussionPanel', 1)[0]
        self.assertNotIn('.onTapGesture', body)
        self.assertIn('Button(action: open)', body)
        self.assertIn('.buttonStyle(QuestifyCardButtonStyle())', body)
        self.assertIn('accessibilityIdentifier("club.discussion.body.\\(post.id)")', body)
        self.assertNotIn('Button(', body.split('private var content', 1)[1])
        feed = source('ClubCommunityViews.swift')
        self.assertIn('@QuestifyReduceMotion private var reduceMotion', feed)
        toggle = feed.split('private func toggleDiscussion', 1)[1].split('\n    }\n', 1)[0]
        self.assertIn('withAnimation(reduceMotion ? nil : QuestifyMotion.content)', toggle)

    def test_payment_success_has_done_crossfade_and_haptic(self):
        text = source('PaymentProviderReturnSheet.swift')
        success = text.split('case .paid, .accepted:', 1)[1].split('case .failed:', 1)[0]
        self.assertIn('Button("action.done")', success)
        self.assertIn('accessibilityIdentifier("contextSelfPlay.result.done")', success)
        self.assertIn('@QuestifyReduceMotion private var reduceMotion', text)
        self.assertIn('.animation(reduceMotion ? nil : QuestifyMotion.content, value: model.flow.phase)', text)
        self.assertIn('.sensoryFeedback(.success, trigger: succeeded)', text)
        # Existing auto-close and dismissal lock stay.
        self.assertIn('2_000_000_000', text)
        self.assertIn('.interactiveDismissDisabled()', text)

    def test_media_gallery_zooms_from_thumbnail_on_ios18_only(self):
        text = source('NativeMediaGallery.swift')
        self.assertIn('@Namespace private var mediaZoomNamespace', text)
        self.assertIn('.matchedTransitionSource(id: id, in: namespace)', text)
        self.assertIn('.navigationTransition(.zoom(sourceID: id, in: namespace))', text)
        self.assertEqual(text.count('if #available(iOS 18.0, *)'), 2)
        self.assertEqual(text.count('enabled: !reduceMotion'), 2)
        self.assertEqual(text.count('.fullScreenCover('), 1)

    def test_spatial_reveal_actions_read_motion_tokens(self):
        text = source('PlayKitSpatialRevealView.swift')
        self.assertEqual(len(re.findall(r'SCNAction\.\w+\([^)]*duration: QuestifyMotionToken\.\w+\)', text)), 4)
        self.assertIsNone(re.search(r'duration: \d', text))


if __name__ == '__main__':
    unittest.main()

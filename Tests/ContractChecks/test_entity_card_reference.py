"""Reference-style source guards; rendered layout and accessibility still require Apple tests."""
import pathlib
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class EntityCardReferenceTests(unittest.TestCase):
    def test_full_bleed_gradient_has_no_outline_or_reference_asset(self):
        source=(ROOT/'App/QuestifyImageEntityCard.swift').read_text()
        for text in ['scaledToFill()','LinearGradient','scrimOpacity','foregroundStyle(.white)','QuestifyCardArtwork.safeURL','QuestifyReduceMotion','colorSchemeContrast']:
            self.assertIn(text,source)
        for text in ['.stroke(','.strokeBorder(','.border(','622cb761b29c81918560af7d58371413','9AE7A155-77DD-44D3-8A49-D47E44997A34']:
            self.assertNotIn(text,source)
        self.assertIn('0.94 : 0.86',source)
        self.assertIn('Text(verbatim:subtitle).font(.subheadline).lineLimit(nil)',source)
        self.assertNotIn('.lineLimit(3)',source)
        self.assertIn('details().font(.subheadline).lineLimit(nil).fixedSize(horizontal:false,vertical:true)',source)
    def test_club_and_topic_use_shared_entity_component(self):
        for filename in ['ClubComponents.swift','TopicBrowserView.swift','HomeFeedView.swift']:
            self.assertIn('QuestifyImageEntityCard(', (ROOT/'App'/filename).read_text())
        club=(ROOT/'App/ClubComponents.swift').read_text()
        self.assertIn('imageSource:club.cover',club)
        self.assertIn('club.memberCount',club)
        self.assertNotIn('Image("',club)

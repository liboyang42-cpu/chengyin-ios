"""P057 static wiring checks only: no Swift typechecking, runtime or Apple evidence."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubStoryNavigationContractTests(unittest.TestCase):
    def text(self, file): return (ROOT / file).read_text()
    def test_route_play_and_chapter_content_is_typed_and_separate(self):
        view = self.text('App/ClubGovernanceViews.swift')
        story = view.split('@MainActor struct ClubGovernanceStoryView:', 1)[1].split('struct ClubGovernanceFactRows:', 1)[0]
        for text in ['ClubStoryPresentation(snapshot:', '.pickerStyle(.segmented)', 'tab == .route',
                     'chapterPicker(presentation.chapters)', 'playContent(chapter)', 'ClubStoryStopCard(',
                     'ClubStoryGameplayCard(', 'storyExpanded ? nil : 4', 'guard presentation?.chapters.contains(chapter) == true']:
            self.assertIn(text, story)
        self.assertNotIn('ClubGovernanceFactRows(', story)
        self.assertNotIn('walkText', story)
    def test_source_bound_navigation_checks_at_selection_and_destination(self):
        view = self.text('App/ClubGovernanceViews.swift')
        for text in ['snapshot: $snapshot, snapshotContext: $snapshotContext, snapshotGeneration: $snapshotGeneration',
                     'context.authorizationGeneration == access.authorizationGeneration',
                     'context.accessIdentity == ObjectIdentifier(access)',
                     'context.readerIdentity == templates.readerIdentity', 'snapshotContext == context',
                     '.onChange(of: sourceRevision)', 'selectedTemplate = nil; selectedAnswer = nil',
                     'selectedTemplate == nil, selectedAnswer == nil',
                     'selectedAnswer == nil, selectedTemplate == nil', '.navigationDestination(item: $selectedTemplate)',
                     'selection.isCurrent(snapshot: snapshot', 'destination(selection.route.templateID)']:
            self.assertIn(text, view)
    def test_destination_reuses_exact_existing_session_reader(self):
        app = self.text('App/ClubStoryViews.swift')
        for text in ['reader: playerJourneyReader', 'SessionMemberTemplateDetailView(id: id).environmentObject(self)',
                     'var reader: (any MemberTemplateReading)? = nil', 'var destination: ((MemberPlayTemplateID) -> AnyView)? = nil',
                     'templates.readerScope == readerScope', 'context.readerIdentity == templates.readerIdentity',
                     'reader?.isAuthenticated == true', 'reader?.isConfigured == true']:
            self.assertIn(text, app)
        for text in ['SessionOwnedMemberTemplateDetailView', 'makeOwnedMemberTemplateReader', 'PublicPlayTemplateID',
                     'readsEnabled: true', 'PlayerJourneySessionReader(', 'api/template/info']:
            self.assertNotIn(text, app)
        session = self.text('App/AppSession.swift')
        self.assertIn('storyTemplates: clubStoryTemplateContext(viewerRevision: compositionViewerRevision)', session)
        self.assertIn('storyTemplates: governance.storyTemplates', self.text('App/ClubDetailView.swift'))
        self.assertIn('.environment(\\.clubStoryTemplates, storyTemplates)', self.text('App/ClubGovernanceViews.swift'))
    def test_answers_keep_separate_protected_read_and_approved_media_pipeline(self):
        view = self.text('App/ClubGovernanceViews.swift')
        cards = self.text('App/ClubStoryViews.swift')
        self.assertIn('ClubGovernanceReadView(operation: .nodeAnswer, scope: target.scope', view)
        self.assertIn('ClubStoryAnswerRoute', view)
        self.assertNotIn('api/play/nodes', view)
        self.assertIn('NativeMediaImage(raw: raw, reader: imageReader ?? RetainedPublicImageReader(), zoomable: false)', cards)
        for text in ['AsyncImage(', 'URLSession', 'approvedHosts:', 'https://', 'WALK_METERS_PER_MIN', 'haversine']:
            self.assertNotIn(text, cards)
    def test_cards_expose_source_fields_and_truthful_absence(self):
        cards = self.text('App/ClubStoryViews.swift')
        for text in ['stop.sequence', 'stop.name', 'stop.businessTime', 'stop.address', 'stop.imgUrl',
                     'chapter.totalTime', 'chapter.stops.count', 'play.validationMethod', 'play.players',
                     'play.duration', 'play.difficulty', 'play.nodeName', 'club.story.hoursUnavailable',
                     'club.story.addressUnavailable', 'club.story.noImage']:
            self.assertIn(text, cards)
    def test_fragment_is_bilingual_and_covers_all_display_keys(self):
        fragment = json.loads(self.text('Resources/ClubStoryLocalizations.fragment.json'))['strings']
        self.assertGreaterEqual(len(fragment), 25)
        sources = self.text('App/ClubStoryViews.swift') + self.text('App/ClubGovernanceViews.swift')
        keys = re.findall(r'(?:Text|Button|Picker|Label)\("(club\.story\.[^"\\]+)"', sources)
        for key in keys:
            self.assertIn(key, fragment)
        for key, item in fragment.items():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][language]['stringUnit']['value'], key)
    def test_fixtures_do_not_construct_real_session_or_grants(self):
        fixture = self.text('App/ClubStoryFixtureHost.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        for text in ['ClubGovernanceFixtureAccess()', 'ClubStoryFixtureMemberReader()', 'ClubStoryFixtureData.value',
                     'member.scope = UUID()', 'revision &+= 1', 'withCheckedThrowingContinuation']:
            self.assertIn(text, fixture)
        for text in ['AppSession(', 'APIConfiguration(', 'readsEnabled: true', 'URLSession', 'approvedHosts']:
            self.assertNotIn(text, fixture)
    def test_authored_unit_and_ui_edges_are_present(self):
        unit = self.text('Tests/AppUnitTests/ClubStoryNavigationTests.swift')
        ui = (self.text('Tests/AppUITests/ClubStoryFlowTests.swift') +
              self.text('Tests/AppUITests/ClubStoryNavigationFlowTests.swift'))
        self.assertEqual(len(re.findall(r'func test\w+', unit)), 6)
        self.assertEqual(len(re.findall(r'func test\w+', ui)), 9)
        for text in ['SessionABAReaderReplacement', 'MissingDestinationSignedOutAndDefaultOff',
                     'DefaultServiceGrantStillPreventsDispatch', 'ExactMyInfoAndRejectsWrongReturnedID']:
            self.assertIn(text, unit)
        for text in ['DelayedDetailCannotReappear', 'BackSupportsRepeatedSelection',
                     'ChineseRoutePlayAndEmptyChapter', 'AccountAndReaderReplacementDismissOldDestination']:
            self.assertIn(text, ui)

if __name__ == '__main__': unittest.main()

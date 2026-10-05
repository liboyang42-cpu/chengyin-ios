"""Source regressions for observed Club Story UI failures; no Apple execution claim."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ClubStoryRuntimeBoundaryChecks(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_fixture_context_wraps_navigation_stack_like_normal_entry(self):
        fixture = self.text('App/ClubStoryFixtureHost.swift')
        stack = fixture.split('NavigationStack {', 1)[1].split('.safeAreaInset', 1)[0]
        self.assertRegex(stack, r'coordinator: store.coordinator\)\s*}\s*//[^\n]*\n\s*\.environment\(\\.clubStoryTemplates, store.templates\)')
        # The production entry already places the same context outside its stack.
        production = self.text('App/ClubGovernanceViews.swift').split('struct ClubGovernanceHomeEntries', 1)[0]
        self.assertIn('NavigationStack { ClubGovernanceWorkspaceView', production)
        self.assertRegex(production, r'coordinator: coordinator\) }\s*\.environment\(')
        self.assertIn('.environment(\\.clubStoryTemplates, storyTemplates)', production)

    def test_gameplay_card_identifier_is_a_leaf_and_does_not_replace_title_identifier(self):
        source = self.text('App/ClubStoryViews.swift').split('struct ClubStoryGameplayCard', 1)[1]
        self.assertIn('.font(.headline).accessibilityIdentifier("club.gov.fact.title")', source)
        self.assertRegex(source, r'Text\("club.story.stop \\\(play.sequence\)"\)\.font\(\.subheadline\)\s*\.accessibilityIdentifier\("club.story.play.\\\(play.id\)"\)')
        self.assertNotRegex(source, r'}\.fixedSize\([^\n]+\)\s*\.accessibilityIdentifier')

    def test_source_reader_owner_and_return_reentry_fences_remain_present(self):
        source = self.text('App/ClubGovernanceViews.swift')
        for guard in ['snapshotContext == context', 'context.authorizationGeneration == access.authorizationGeneration',
                      'context.accessIdentity == ObjectIdentifier(access)', 'context.readerIdentity == templates.readerIdentity',
                      '.onChange(of: sourceRevision)', '.onChange(of: tab)', '.refreshable { await reload() }']:
            self.assertIn(guard, source)
        selection = self.text('App/ClubStoryViews.swift').split('struct ClubStoryTemplateSelection', 1)[1].split('struct ClubStoryEmptyState', 1)[0]
        self.assertIn('templates.readerScope == readerScope', selection)
        self.assertIn('context.readerIdentity == templates.readerIdentity', selection)
        self.assertIn('snapshotGeneration: snapshotGeneration', selection)

    def test_existing_ui_journeys_still_require_exact_tabs_and_replacement_boundaries(self):
        for file in ['ClubStoryFlowTests.swift', 'ClubStoryNavigationFlowTests.swift']:
            source = self.text('Tests/AppUITests/' + file)
            self.assertIn('app.segmentedControls["club.story.tabs"].waitForExistence(timeout: 5)', source)
            self.assertIn('revealFixtureElement(button, in: app)', source)
        nav = self.text('Tests/AppUITests/ClubStoryNavigationFlowTests.swift')
        for target in ['club.story.fixture.account', 'club.story.fixture.reader', 'club.story.fixture.refresh',
                       'club.story.fixture.finish', 'Synthetic personal template 142']:
            self.assertIn(target, nav)
        fixture = self.text('App/ClubStoryFixtureHost.swift')
        for forbidden in ['AppSession(', 'URLSession', 'ReadApproval(', 'APIConfiguration(']:
            self.assertNotIn(forbidden, fixture)

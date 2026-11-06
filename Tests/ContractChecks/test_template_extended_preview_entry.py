"""Source integration checks only; not Swift compilation or App execution."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ExtendedPreviewEntry(unittest.TestCase):
    def test_all_five_routes_validate_and_reuse_existing_views(self):
        s=(ROOT/'App/TemplateConfiguredRehearsalPreview.swift').read_text()
        for g in ['sort','match','classify','compass','shout']:
            cls='TemplateReasoningRehearsal' if g in ['sort','match','classify'] else 'TemplateSensorRehearsal'
            self.assertIn(f'case .{g}: return .{g}',s)
            self.assertIn(f'{cls}(draft.advanced, game: .{g}) != nil',s)
            self.assertIn(f'{cls}View(model: model, game: .{g})',s)
    def test_summary_prefers_owned_route_over_readonly_mini_preview(self):
        s=(ROOT/'App/TemplateAuthoringView.swift').read_text().split('ForEach(draft.advanced.enabledGames) { game in')[1]
        self.assertLess(s.index('configuredRehearsals.route(for: game)'),s.index('game.isMiniProgramAddition'))
    def test_existing_lifetime_and_validation_gates_preserved(self):
        s=(ROOT/'App/TemplateConfiguredRehearsalPreview.swift').read_text()
        for x in ['guard isCurrent else','guard supported && draft.advanced.enabled(game.section)','self.generation == stamp','owner == model.coordinator.session','source == TemplateSamplePreview.snapshot(model.draft)','path == [destination]']:
            self.assertIn(x,s)
        for x in ['URLSession','AVAudioSession','CLLocationManager','submitCompletion']:
            self.assertNotIn(x,s)
    def test_native_fixture_and_legacy_expectations_match_extended_routes(self):
        s=(ROOT/'Tests/AppUnitTests/TemplateConfiguredRehearsalPreviewTests.swift').read_text()
        valid=s.split('func testExtendedRoutesRequireValidatedConfigurationAndRetireOnBackground')[1].split('func testExtendedRoutesRejectDisabledAndMalformedDrafts')[0]
        self.assertIn('set("compass", "bearing", .number(90))',valid)
        legacy=s.split('func testD20MiniAndDeviceGamesKeepTheirExistingBranches')[1].split('func testMalformedAndDisabledConfigurationCannotOpen')[0]
        self.assertIn('[TemplateAdvancedGame.shake, .quiet]',legacy)
        for game in ['sort','match','classify','compass','shout']:
            self.assertNotIn('.'+game,legacy)
        invalid=s.split('func testExtendedRoutesRejectDisabledAndMalformedDrafts')[1].split('func testNewAndInactiveOwner')[0]
        self.assertIn('setGameEnabled(game, malformed)',invalid)
        self.assertIn('XCTAssertTrue(model.draft.advanced.enabled(game.section))',invalid)
        for token in ['"prompt", .string("")','"bearing", .number(360)','"seconds", .number(-1)']:
            self.assertIn(token,invalid)
if __name__=='__main__': unittest.main()

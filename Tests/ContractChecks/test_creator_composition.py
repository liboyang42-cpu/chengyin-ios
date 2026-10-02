"""Offline shape checks plus optional execution of the current mini validator.
Swift/Apple/runtime acceptance is reported independently.
"""
import json, os, pathlib, re, subprocess, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class CreatorCompositionChecks(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_single_selection_api_and_guard_are_removed(self):
        text = self.read('Core/TemplateAdvancedDraft.swift')
        self.assertNotIn('func select(', text)
        self.assertNotIn('var selected:', text)
        self.assertNotIn('issue("oneGame")', text)
        self.assertIn('public var enabledGames:', text)
        body = text.split('public mutating func setGameEnabled', 1)[1].split('public mutating func setNested', 1)[0]
        self.assertIn('set(game.section, "enabled", .bool(enabled))', body)
        self.assertNotIn('allCases', body)
    def test_every_game_has_an_independent_addressed_editor(self):
        menu = self.read('App/TemplateAuthoringDetailForms.swift')
        detail = self.read('App/TemplateAdvancedGameConfigurationView.swift')
        self.assertIn('ForEach(TemplateAdvancedGame.allCases)', menu)
        self.assertIn('TemplateAdvancedGameConfigurationView(model: model, game: game)', menu)
        self.assertIn('setGameEnabled(game, enabled)', detail)
        self.assertIn('creatorComposition.enabled.', detail)
        self.assertNotIn('supportsTimer', menu)
        self.assertNotIn('gamePicker', menu)
    def test_presentation_aggregates_all_active_families(self):
        model = self.read('Core/TemplateAdvancedDraft.swift')
        self.assertIn('enabledGames.contains { !$0.allowsInline }', model)
        self.assertIn('enabledCreatorFamilies.contains { $0.fullscreenOnly }', model)
        self.assertIn('explicitPresentation == "inline", presentationRequiresFullscreen', model)
    def test_review_and_preview_are_plural(self):
        text = self.read('App/TemplateAuthoringView.swift')
        self.assertIn('ForEach(draft.advanced.enabledGames)', text)
        self.assertIn('ForEach(draft.advanced.enabledConfigurationLabelKeys', text)
        self.assertNotIn('advanced.selected', text)
    def test_bilingual_composition_copy_is_keyed(self):
        fragment = json.loads(self.read('Resources/CreatorCompositionLocalizations.fragment.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 3)
        for key, entry in fragment.items():
            self.assertEqual(entry, catalog[key]); self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
    def test_no_new_transport_or_role_assignment(self):
        ui = self.read('App/TemplateAdvancedGameConfigurationView.swift')
        for token in ['URLSession', 'sendEvent(', 'transport', 'assignRole', 'ProductionTransport']: self.assertNotIn(token, ui)
    def test_compound_fixture_reuses_existing_dormant_host(self):
        self.assertIn('--template-author-compound', self.read('App/TemplateAuthoringFixtureSupport.swift'))
        self.assertIn('compoundAdvanced', self.read('Core/TemplateAuthoringSyntheticFixtures.swift'))

class CreatorCompositionSourceChecks(unittest.TestCase):
    def test_current_mini_compound_and_cross_family_contracts(self):
        source = os.environ.get('CHENGYIN_MINI_SOURCE_ROOT')
        if not source: self.skipTest('Current mini checkout not provided; native assertions still ran')
        module = pathlib.Path(source) / 'pages/publish/utils/publish/advanced-game-config.js'
        self.assertTrue(module.is_file(), str(module))
        fixture = re.search(r'compoundAdvanced = #"(.*?)"#', (ROOT/'Core/TemplateAuthoringSyntheticFixtures.swift').read_text()).group(1)
        script = r'''
const a = require(process.argv[1]); const seed = JSON.parse(process.argv[2]);
const results = [];
function check(name, change, expected) {
  const value = Object.assign(a.defaultConfig(), JSON.parse(JSON.stringify(seed))); change(value);
  const error = a.validate(value); const accepted = !error;
  if (accepted !== expected) throw new Error(name + ': unexpected validation result ' + error);
  if (accepted) {
    const wire = a.serialize(value), restored = a.parse(wire).value;
    if (a.validate(restored)) throw new Error(name + ': reopen failed');
    for (const key of a.enabledSections(value)) if (!restored[key].enabled) throw new Error(name + ': lost ' + key);
  }
  results.push({name, accepted});
}
check('coin+dice+quiet+timer+timeWindow', () => {}, true);
check('coin+dice explicitly fullscreen', x => {x.present='fullscreen'}, true);
check('coin disallows global inline', x => {x.present='inline'}, false);
check('dice+quiet supports global inline', x => {x.coinFlip.enabled=false; x.present='inline'}, true);
check('later compass still disallows inline', x => {x.coinFlip.enabled=false;x.present='inline';x.compass.enabled=true;x.compass.bearing=90}, false);
check('creator steps disallows global inline', x => {x.coinFlip.enabled=false;x.present='inline';x.steps.enabled=true}, false);
check('invalid sibling cannot hide behind valid coin', x => {x.diceRoll.faces=[]}, false);
check('timer remains independent from coin and dice', x => {x.timer.durationSeconds=60}, true);
check('compound adaptive rule', x => {x.reaction.enabled=true;x.variants=[{when:{var:'sys.hp',op:'LTE',value:3},relax:{'timer.durationSeconds':'+30','quietHold.seconds':'-5','reaction.goalMs':'+100'}}]}, true);
check('disabled adaptive operand rejects', x => {x.quietHold.enabled=false;x.variants=[{when:{var:'sys.hp',op:'LTE',value:3},relax:{'quietHold.seconds':'-5'}}]}, false);
process.stdout.write(JSON.stringify(results));
'''
        result = subprocess.run(['node', '-e', script, str(module.resolve()), fixture], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)), 10)

if __name__ == '__main__': unittest.main()

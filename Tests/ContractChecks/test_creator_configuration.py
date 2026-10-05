"""Source-contract checks only; not Swift, Apple or gameplay execution."""
import json, re, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FAMILIES=set('random branch leaderboard multiplayer timeWindow blindTaste silentOrder diyName musicCorner steps dailySign slowTask estimate pricePair hiddenObject predict qa scan album profile photoCheck check note typeIn compare'.split())
class CreatorConfigurationChecks(unittest.TestCase):
    @classmethod
    def setUpClass(c):
        c.schema=(ROOT/'Core/TemplateCreatorSchema.swift').read_text()
        c.model=(ROOT/'Core/TemplateCreatorConfiguration.swift').read_text()
        c.draft=(ROOT/'Core/TemplateAdvancedDraft.swift').read_text()
        c.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        c.preview=(ROOT/'App/TemplateCreatorRehearsalView.swift').read_text()
        c.rehearsal=(ROOT/'Core/TemplateCreatorRehearsal.swift').read_text()
        c.catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
    def test_exact_remaining_registry(self):
        body=self.schema.split('public var id:',1)[0]
        names=set(', '.join(re.findall(r'\bcase ([^\n]+)',body)).replace(',',' ').split())
        self.assertEqual(names,FAMILIES)
    def test_retired_panels_absent(self):
        for name in ['gameTimer','stickerBook']:self.assertNotIn(name,self.schema)
    def test_case_specific_schemas(self):
        for name in FAMILIES:
            self.assertRegex(self.schema,rf'case \.{name}\s*:')
            self.assertIn('creator.family.'+name,self.catalog)
    def test_editor_and_review_mounts(self):
        editor=(ROOT/'App/TemplateAuthoringDetailForms.swift').read_text()
        review=(ROOT/'App/TemplateAuthoringView.swift').read_text()
        self.assertIn('ForEach(TemplateCreatorFamily.allCases)',editor)
        self.assertIn('TemplateCreatorConfigurationView(model: model, family: family)',editor)
        self.assertIn('draft.advanced.enabledCreatorFamilies',review)
    def test_typed_controls_not_json_editor(self):
        for token in ['case .number','case .choice','case .toggle','case .rows','case .object','case .strings','case .poems','case .stateValue','Slider(','.onMove','.onDelete']:self.assertIn(token,self.form)
        self.assertNotIn('TextEditor',self.form);self.assertNotIn('JSONEncoder',self.form)
    def test_source_wire_values(self):
        for token in ['["ELAPSED_TIME", "SCORE", "COMPLETED_UNITS"]','["ACTIVITY", "TOPIC"]','["SEQUENTIAL", "ROLE_BASED"]','["AUTO", "LEADER"]','["TYPE", "PICK", "SHOT"]','["TEXT", "VOICE", "IMAGE", "OVERLAY"]','["NONE", "PLANE", "MARKER"]','["retake", "pass"]']:self.assertIn(token,self.schema)
    def test_backend_boundaries(self):
        for token in ['n("tries", 0, 10, 0)','media("frameUrl", 512)','n("goal", 100, 100000, 6000)','n("waitDays", 1, 7, 1)','n("maxLength", 1, 40, 40)']:self.assertIn(token,self.schema)
        for token in ['unreachable','var optionKeys = Set<String>()','question["required"] = .bool(true)']:self.assertIn(token,self.model)
    def test_unknowns_and_absent_secrets_fail_closed(self):
        for token in ['creatorUnknownIssues','retainCreatorSecretAbsence(incoming)','if !Self.defaults.keys.contains(key) { value[key] = entry; continue }']:self.assertIn(token,self.draft)
        self.assertIn('fields[key] = patch(fields[key]',self.model)
    def test_state_tags_use_value_not_a_fabricated_field(self):
        self.assertIn('.init("value", .stateValue',self.schema)
        self.assertNotIn('t("tag",',self.schema)
        self.assertIn('variable == "sys.luck"',self.model)
        self.assertIn('(mistakes|outcome|passed)',self.model)
    def test_normalization_and_size_limit(self):
        self.assertIn('normalized.normalizeCreatorFamilies()',self.draft)
        self.assertIn('data.count <= 65_536',self.draft)
        self.assertIn('removeValue(forKey: "frameOpacity")',self.model)
    def test_no_provider_calls_or_live_mutations(self):
        text=self.model+self.form+self.preview+self.rehearsal
        for token in ['URLSession','submit(','sendEvent(','capabilityGrant','ProductionTransport','AVCaptureSession','CMPedometer']:self.assertNotIn(token,text)
        self.assertIn('providerRequired',self.rehearsal)
    def test_bilingual_strings(self):
        owned=[key for key in self.catalog if key.startswith('creator.')]
        self.assertGreaterEqual(len(owned),250)
        for key in owned:
            for lang in ['en','zh-Hans']:self.assertTrue(self.catalog[key]['localizations'][lang]['stringUnit']['value'].strip(),(key,lang))
    def test_each_enum_value_has_localized_label(self):
        for block in re.findall(r'c\("[^"]+", \[([^\]]+)\]',self.schema):
            for value in re.findall(r'"([^"]*)"',block):self.assertIn('creator.choice.'+(value or 'empty'),self.catalog)
    def test_authored_swift_tests_cover_every_family(self):
        tests=(ROOT/'Tests/CoreTests/TemplateCreatorConfigurationTests.swift').read_text()
        self.assertEqual(set(re.findall(r'case \.(\w+): raw =',tests)),FAMILIES)
        for name in ['testAllTwentyFiveFamiliesSerializeReopenAndReserialize','testEveryTopLevelNumberRejectsOutOfBoundsAndBlank','testUnknownNestedFieldsSurviveSnapshotAndBlockReserialization','testMissingProviderDoesNotPreventAuthoringOrInventVerification']:self.assertIn(name,tests)

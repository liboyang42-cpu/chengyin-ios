import json, re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class CreatorContentContracts(unittest.TestCase):
    def setUp(self):
        self.service=(ROOT/'Core/CreatorContentService.swift').read_text()
        self.reader=(ROOT/'Core/CreatorContentReading.swift').read_text()
        self.ui=(ROOT/'App/CreatorContentViews.swift').read_text()
    def test_only_audited_read_routes(self):
        self.assertEqual(set(re.findall(r'"(api/[^\"]+)"',self.service)), {'api/project/my','api/creator/center'})
    def test_fixed_source_page(self):
        for pair in ['"pageNum": "1"','"pageSize": "200"','"ownerType": query.ownerType']:
            self.assertIn(pair,self.service)
        self.assertNotIn('loadMore',self.ui)
    def test_session_guard_precedes_unauthorized_callback(self):
        catch=self.reader[self.reader.index('        } catch {'):]
        self.assertLess(catch.index('currentSession() == session'),catch.index('onUnauthorized(session)'))
        self.assertIn('try Task.checkCancellation()', self.reader)
        self.assertIn('scope == captured', self.reader)
    def test_ui_shared_artwork_and_no_fake_writes(self):
        self.assertIn('QuestifyImageEntityCard',self.ui)
        self.assertNotIn('apply(',self.ui);self.assertNotIn('delete(',self.service)
        self.assertIn('creatorContent.readOnly',self.ui)
    def test_retry_identifier_not_on_ancestor(self):
        self.assertIn('}.accessibilityIdentifier("creatorContent.issue")',self.ui)
        self.assertNotIn('issue(failure).accessibilityIdentifier', self.ui)
    def test_localization_static_keys_and_dynamic_families(self):
        strings=json.loads((ROOT/'docs/creator-content-localizations.json').read_text())
        for key in re.findall(r'"(creatorContent\.[^"\\]+)"',self.ui):
            if key not in ['creatorContent.issue','creatorContent.status','creatorContent.filter.','creatorContent.status.']:
                self.assertIn(key,strings)
        for value in strings.values(): self.assertEqual(set(value),{'en','zh-Hans'})
    def test_identity_and_unknown_state(self):
        contracts=(ROOT/'Core/CreatorContentContracts.swift').read_text()
        self.assertIn('"\\(bizType):\\(sourceID)"',contracts)
        self.assertIn('?? .unknown',contracts)
    def test_dynamic_localization_uses_concatenated_string(self):
        self.assertIn('LocalizedStringKey("creatorContent.filter." + value)', self.ui)
        self.assertIn('LocalizedStringKey("creatorContent.status." + center.status.rawValue)', self.ui)
        self.assertNotIn('LocalizedStringKey("creatorContent.filter.' + chr(92) + '(', self.ui)
        self.assertNotIn('LocalizedStringKey("creatorContent.status.' + chr(92) + '(', self.ui)
    def test_explicit_play_template_destination(self):
        contracts=(ROOT/'Core/CreatorContentContracts.swift').read_text()
        self.assertIn('case "template": return .playTemplate(sourceID)', contracts)
        self.assertNotIn('case "topicTemplate"', contracts)
    def test_authoring_inventory(self):
        tests=(ROOT/'Tests/CoreTests/CreatorContentTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+',tests)),21)
if __name__=='__main__': unittest.main()

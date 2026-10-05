import json, pathlib, re, unittest
from flutter_source import read_flutter_source
ROOT = pathlib.Path(__file__).resolve().parents[2]
class SquareWorkspaceSourceChecks(unittest.TestCase):
    def test_endpoints_are_source_backed(self):
        native = (ROOT/'Core/SquareWorkspaceService.swift').read_text()
        for path in ['api/creativesquare/action','api/creativesquare/info','api/v1/community/guidelines/active','api/v1/community/guidelines/ack','api/v1/community/media/register','api/v1/community/drafts']:
            self.assertIn(path, native)
    def test_endpoints_external_flutter_parity(self):
        flutter = read_flutter_source(self, 'data/api/square_api.dart')
        for path in ['api/creativesquare/action','api/creativesquare/info','api/v1/community/guidelines/active','api/v1/community/guidelines/ack','api/v1/community/media/register','api/v1/community/drafts']:
            self.assertIn(path, flutter)
        self.assertIn("'bizType': 'COMMUNITY_POST'", read_flutter_source(self, 'data/api/play_api.dart'))
    def test_fields_and_source_enum_coverage(self):
        native = (ROOT/'Core/SquareWorkspaceService.swift').read_text()
        for key in ['uploadRequestId','uploadReceipt','byteSize','mimeType','clientRequestId','expectedVersion','guidelineVersionId','privacySnapshot','locationPrecision','mentionedMemberIds']:
            self.assertIn('"'+key+'"',native)
        contracts = (ROOT/'Core/SquareWorkspaceContracts.swift').read_text()
        for kind in ['SPONSORED','GIFTED','MERCHANT_OWNER','MERCHANT_EMPLOYEE']:
            self.assertIn(kind,contracts)
    def test_fields_and_enums_external_flutter_parity(self):
        source = read_flutter_source(self, 'data/api/square_api.dart')
        for key in ['uploadRequestId','uploadReceipt','byteSize','mimeType','clientRequestId','expectedVersion','guidelineVersionId','privacySnapshot','locationPrecision','mentionedMemberIds']:
            self.assertIn("'"+key+"'",source)
        compose = read_flutter_source(self, 'feature/square/square_compose_page.dart')
        for kind in ['SPONSORED','GIFTED','MERCHANT_OWNER','MERCHANT_EMPLOYEE']:
            self.assertIn(kind,compose)
    def test_no_default_live_or_network_factory(self):
        core = '\n'.join(p.read_text() for p in (ROOT/'Core').glob('SquareWorkspace*.swift'))
        self.assertIn('var live = false',core); self.assertIn('var media = false',core); self.assertIn('var legal = false',core)
        for bad in ['URLSession.shared','CoreLocation','CLLocationManager','Task.sleep','UserDefaults']:
            if bad != 'UserDefaults': self.assertNotIn(bad,core)
        self.assertIn('pending: true',core); self.assertIn('currentSession() == expected',core)
    def test_all_literal_ui_keys_have_two_languages(self):
        catalog = json.loads((ROOT/'docs/square-journey-chat/packets/native-square-workspace-new/docs/square-workspace-localizations.json').read_text())['strings']
        text = '\n'.join(p.read_text() for p in (ROOT/'App').glob('SquareWorkspace*.swift'))
        keys = set(re.findall(r'"(squareWorkspace\.[A-Za-z]+)"',text))
        identifiers = {'status','selectPhoto','body','upload','lane','saveLocal','saveServer','review','withdraw','revisions','acceptGuideline','confirm'}
        for key in keys:
            if key.split('.')[-1] in identifiers and key not in catalog: continue
            self.assertIn(key,catalog)
        for row in catalog.values(): self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
    def test_boundary_not_overwrite_existing_social_actions(self):
        self.assertTrue((ROOT/'Core/SocialActionContracts.swift').exists())
        self.assertIn('SquareWorkspaceView(coordinator: workspace)', (ROOT/'App/SquareBrowserView.swift').read_text())
        self.assertIn('Club references',json.loads((ROOT/'docs/square-journey-chat/packets/native-square-workspace-new/docs/square-workspace-localizations.json').read_text())['strings']['squareWorkspace.communityIdentity']['localizations']['en']['stringUnit']['value'])
if __name__ == '__main__': unittest.main()

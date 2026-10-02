"""Source inspection and offline structure, never Swift execution."""
import json, pathlib, subprocess, sys, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'app-audit'
class SearchMapSourceChecks(unittest.TestCase):
    def text(self, path): return (ROOT/path).read_text()
    def test_standalone_structural_checks(self):
        subprocess.run([sys.executable,str(ROOT/'tools/check_search_map.py'),'--root',str(ROOT)],check=True,capture_output=True)
    def test_source_backing_when_flutter_available(self):
        if not (SOURCE/'lib/feature/search/search_controller.dart').is_file(): self.skipTest('Preserved Flutter source not present')
        subprocess.run([sys.executable,str(ROOT/'tools/check_search_map.py'),'--root',str(ROOT),'--flutter',str(SOURCE)],check=True,capture_output=True)
    def test_distinct_home_global_entry_and_fixture(self):
        home=self.text('App/SessionHomeFeedView.swift');fixture=self.text('App/ModuleFixtureSupport.swift')
        self.assertIn('homeFeed.openGlobalSearch',home);self.assertIn('SessionGlobalSearchView(',home)
        self.assertIn('.id(session.searchMapReader.scope)',home);self.assertIn('case .searchMap: SearchMapFixtureHostView()',fixture)
    def test_configuration_and_captured_auth_scope(self):
        session=self.text('App/AppSession.swift')
        self.assertIn('if let scope, let regional, let configuration=regional.apiConfiguration',session)
        self.assertIn('searchMapService=SearchMapService(configuration:configuration,transport:transport)',session)
        self.assertIn('self.currentSearchMapContext == captured',session)
        self.assertIn('storageScope.service + ".search."',session)
    def test_typed_destinations_do_not_open_internal_merchant_console(self):
        app=self.text('App/SessionGlobalSearchView.swift')
        for view in ['ActivityDetailView','TopicDetailView','ClubDetailView','SearchMapMerchantDetailView','SearchMapCityDetailView']:self.assertIn(view,app)
        self.assertNotIn('MerchantHomeView',app)
        self.assertNotIn('templateID',app)
    def test_city_node_related_destination_has_explicit_builder_and_merchant_only_boundary(self):
        # Source regression only: the generic stored closure is not itself a ViewBuilder.
        app=self.text('App/SessionGlobalSearchView.swift')
        self.assertIn('SearchMapCityDetailView(id: id, reader: session.searchMapReader, destination: cityNodeRelatedDestination)',app)
        marker='@ViewBuilder private func cityNodeRelatedDestination(_ related: SearchMapDestination) -> some View {'
        self.assertIn(marker,app)
        helper=app.split(marker,1)[1]
        self.assertIn('if case .merchant(let merchantID) = related {',helper)
        self.assertIn('SearchMapMerchantDetailView(id: merchantID, reader: session.searchMapReader)',helper)
        # With no else branch, unsupported related destinations remain empty.
        for forbidden in ['else', 'destination(', '.activity', '.topic', '.club', '.cityNode', 'templateID']:
            self.assertNotIn(forbidden,helper)
    def test_no_location_permission_or_provider_actions(self):
        app='\n'.join(p.read_text() for p in (ROOT/'App').glob('*Search*swift'))
        for action in ['CLLocationManager','requestWhenInUseAuthorization','startUpdatingLocation','MKDirections(','openInMaps(','openURL(']:self.assertNotIn(action,app)
        self.assertIn('if offline {',self.text('App/SearchMapCanvas.swift'))
    def test_authored_adversarial_tests_are_retained(self):
        core=self.text('Tests/CoreTests/SearchMapTests.swift')
        for name in ['testAccountTokenEpochAndGuestTransitionsDropStaleSuccessAndUnauthorized','testGuestCitySearchKeepsActivitiesAndDoesNotCallPrivateNodes','testCurrentAggregate401ExpiresOnlySignedInContext','testTypedDestinationAndMerchantIDDoNotUseMemberID','testReverseFailureDoesNotHideNearbyButAuthenticated401IsNotSwallowed']:self.assertIn(name,core)
        self.assertIn('testSessionSwitchClearsResultsAndCityData',self.text('Tests/AppUITests/SearchMapFlowTests.swift'))
    def test_catalog_matches_fragment_and_has_no_language_based_region(self):
        entries=json.loads(self.text('docs/search-map-localizations.json'));catalog=json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        for key, values in entries.items():
            for language,text in values.items():self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'],text)
        self.assertNotIn('AppleLanguages',self.text('Core/SearchMapService.swift'))
if __name__=='__main__':unittest.main()

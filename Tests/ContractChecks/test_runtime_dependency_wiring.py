"""Supplementary source assertions; fake Swift tests are authored, not executed here."""
import json, pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class RuntimeDependencyWiringTests(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_shipped_root_preserves_all_configuration_gates(self):
        self.assertIn('session=AppSession()', self.read('App/QuestifyApp.swift'))
        session = self.read('App/AppSession.swift')
        self.assertIn('self.runtimeDependencies = runtimeDependencies ?? .dormant', session)
        launch = self.read('App/RegionalLaunchConfiguration.swift')
        self.assertIn('let approved:[RegionalMarket:Set<String>]=[:]', launch)
        self.assertIn('verifiedCapabilities:[]', launch)
        defaults = self.read('App/NativeRuntimeDependencies.swift')
        for value in ['RuntimeDependencyConfiguration? = nil', '(any HTTPTransport)? = nil', '(any RoamDeviceLocationProviding)? = nil', 'ShopNPCGrants = .init()', '(any PlayMotionSampleProviding)? = nil']:
            self.assertIn(value, defaults)
    def test_exact_account_region_namespace_origin_and_role_epoch_token_binding(self):
        core = self.read('Core/RuntimeDependencyConfiguration.swift')
        for value in ['market == .china', 'context.market == market', 'endpoints.baseURL == context.baseURL', 'endpoints.namespace == context.session.namespace', 'endpoints.accountID == context.session.accountID', 'current() == captured', 'captured.session.token', 'endpoints.paths.contains', 'components.query = nil']:
            self.assertIn(value, core)
        self.assertEqual(core.count('transport.send(request)'), 1)
        self.assertNotIn('URLSession', core)
        self.assertIn('let role: String', core)
    def test_network_capabilities_and_publisher_mutations_are_independent(self):
        core = self.read('Core/RuntimeDependencyConfiguration.swift')
        for value in ['play: Set<PlayExperienceCapability> = []', 'journeyReads: Bool = false', 'journeyChecks: Bool = false', 'journeyCollect: Bool = false', 'publisherReads: Bool = false', 'nearbyLocation: Bool = false', 'devices: Set<PlayDeviceKind> = []', 'sensors: Set<PlayKitSensorKind> = []', 'shopNPCWrites: Bool = false']:
            self.assertIn(value, core)
        self.assertIn('enabled: accepted?.play ?? []', core)
        self.assertIn('PublisherLifecycleGrants(reads:', core)
        for mutation in ['pricing:', 'cancellationRefunds:', 'ownership:', 'graduation:', 'creatorApplication:']:
            self.assertNotIn(mutation, core)
    def test_factories_mount_production_clients_instead_of_fixtures(self):
        app = self.read('App/AppSession.swift')
        for value in ['runtimeDependencyFactory?.playService()', 'runtimeDependencyFactory?.journeyService()', 'grants: factory.publisherGrants', 'transport: factory.transport', 'CoopFlowService(configuration: api, transport: factory.transport)', 'provider: scopedPlayDeviceProvider()', 'provider: makeRuntimeMotionProvider()']:
            self.assertIn(value, app)
        self.assertNotIn('PlaySyntheticDeviceProvider', app)
        self.assertNotIn('PlayExperienceSyntheticFixtures', app)
    def test_both_nested_and_inline_playkit_hosts_receive_typed_configuration(self):
        for file in ['App/SessionPlayRuntimeView.swift', 'App/PlayExperienceView.swift', 'App/ChapterStoryView.swift']:
            text = self.read(file)
            for value in ['approvedArtworkHosts:', 'makeSensorProvider:', 'spatialApproval:']: self.assertIn(value, text)
        self.assertIn('PlayKitNativeSensorProvider(grants: accepted.sensors)', self.read('App/AppSession.swift'))
    def test_nearby_page_is_mounted_through_normal_environment(self):
        self.assertIn('cooperationNearbyDestination', self.read('App/QuestifyApp.swift'))
        self.assertIn('if let nearbyDestination { nearbyDestination() }', self.read('App/CooperationFlowWorkbench.swift'))
        view = self.read('App/NearbyMerchantView.swift')
        for value in ['model.search(purposeAccepted: purposeAccepted)', 'ownerMemberID(owner)', 'row.memberID', '.onDisappear { cancel() }', 'phase == .background']:
            self.assertIn(value, view)
        self.assertNotIn('.task {', view)
    def test_nearby_requires_consent_fresh_real_fix_and_source_conversion(self):
        core = self.read('Core/NearbyMerchantCoordinator.swift')
        for value in ['guard purposeAccepted', 'guard available', 'location.currentFix()', 'RuntimeLocationProjection.gcj02', 'reader.session == session', '.nearby(longitude:', 'phase == .locating ? .locationFailed : .failed', 'stamp == generation']:
            self.assertIn(value, core)
        self.assertEqual(core.count('reader.read('), 1)
        self.assertNotIn('UserDefaults', core)
        self.assertNotIn('RoamSearchArea', core)
        conversion = self.read('Core/RuntimeLocationProjection.swift')
        for value in ['6378245.0', '0.00669342162296594323', 'fix.datum == .gcj02', 'fix.accuracyMeters <= 100', 'timeIntervalSince(fix.measuredAt)) <= 30']:
            self.assertIn(value, conversion)
    def test_native_location_and_motion_are_user_triggered_and_cancelable(self):
        provider = self.read('App/RuntimeNativeLocationProvider.swift')
        for value in ['enabled: Bool = false', 'NSLocationWhenInUseUsageDescription', 'withTaskCancellationHandler', 'pendingID == id', 'self.manager === manager', 'manager?.stopUpdatingLocation()', 'datum: .wgs84']:
            self.assertIn(value, provider)
        runtime = self.read('App/RuntimePlayDeviceProvider.swift')
        for value in ['isCurrent()', 'native.supported.intersection(grants)', 'RuntimeLocationProjection.gcj02', 'authorizing.prepare(.acceleration)', 'self.provider.samples(.acceleration)', 'self.generation == generation']:
            self.assertIn(value, runtime)
    def test_cancelled_tasks_check_scope_before_opening_sensor_stream(self):
        sensor = self.read('App/RuntimePlayKitSensorProvider.swift')
        guard = 'guard self.isCurrent(), self.generation == generation, !Task.isCancelled'
        self.assertLess(sensor.index(guard), sensor.index('self.provider.samples(kind)'))
        motion = self.read('App/RuntimePlayDeviceProvider.swift')
        self.assertLess(motion.index('guard self.available, self.generation == generation, !Task.isCancelled'), motion.index('authorizing.prepare(.acceleration)'))
    def test_session_changes_cancel_private_runtime_consumers(self):
        app = self.read('App/AppSession.swift')
        for value in ['retainedNativePlayDevice?.provider.cancel()', 'retainedPlayDevices.values.forEach { $0.cancel() }', 'retainedPlayStillness.values.forEach { $0.pause() }', 'retainedPlayPrefabs.values.forEach { $0.cancelDeviceWork() }', 'playExperienceCoordinators.values.forEach { $0.invalidate() }', 'retainedNearbyMerchants?.coordinator.cancel()', 'epoch: gate.currentStamp, role: account?.effectiveRole']:
            self.assertIn(value, app)
    def test_strings_and_fake_tests_exist(self):
        fragment = json.loads(self.read('Resources/RuntimeDependencyLocalizations.fragment.json'))['strings']
        actual = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, value in fragment.items():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'}); self.assertEqual(actual[key], value)
        self.assertEqual(self.read('Tests/CoreTests/RuntimeDependencyTests.swift').count('func test'), 8)
        self.assertEqual(self.read('Tests/CoreTests/NearbyMerchantCoordinatorTests.swift').count('func test'), 10)
        self.assertEqual(self.read('Tests/AppUnitTests/RuntimeDependencyAppTests.swift').count('func test'), 5)
if __name__ == '__main__': unittest.main()

"""Supplementary source assertions; Swift and UI behavior require the Apple toolchain."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CityPointSelectionContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/CityPlayerView.swift').read_text()
        self.core = (ROOT / 'Core/CityPointSelection.swift').read_text()
        self.reader = (ROOT / 'Core/CityPlayerReading.swift').read_text()

    def test_normal_city_map_reuses_reviewed_density_without_parallel_grouping(self):
        for marker in ['QuestifyDensityMap(', 'pins: pins, selectedID: selected?.pointId',
                       'interactionID: context.readID', '.id(context.readID)',
                       'pinIdentifierPrefix: "city.read.pin."', 'onSelect: { id in select(id, rendered: context) }']:
            self.assertIn(marker, self.view)
        self.assertNotRegex(self.view, r'\bMap\s*\{')
        for denied in ['Annotation(', 'MapMarkerDensity.groups(', 'group.members.first']:
            self.assertNotIn(denied, self.view)
        shared = (ROOT / 'App/QuestifyDensityMap.swift').read_text()
        for marker in ['proxy.convert', 'MapMarkerDensity.groups', 'mapDensity.member.',
                       'renderedExpansionID == expansionID', 'currentPins.contains(where: { $0 == pin })',
                       '.onChange(of: interactionID)']:
            self.assertIn(marker, shared)

    def test_map_context_is_issued_only_from_current_authorized_reader_state(self):
        for marker in ['guard case .available(let snapshot) = state else { return nil }',
                       'CityPointMapContext(readID: generation, snapshot: snapshot)',
                       'isConfigured ? stored : .unavailable', 'generation = stamp',
                       'generation = UUID(); pendingLoad?.cancel(); pendingLoad = nil; stored = .unavailable']:
            self.assertIn(marker, self.reader)
        self.assertIn('init?(readID: UUID, snapshot: CityReadSnapshot)', self.core)
        self.assertNotIn('public init?(readID:', self.core)
        for marker in ['snapshot.membership != .unavailable', 'let points = snapshot.points',
                       'points.count <= 200', 'Set(points.map(\\.pointId)).count == points.count',
                       'snapshot.participation?.valid == true']:
            self.assertIn(marker, self.core)

    def test_selection_revalidates_full_snapshot_and_read_identity_on_every_tap(self):
        for marker in ['public let readID: UUID', 'public let snapshot: CityReadSnapshot',
                       'guard rendered == current', '$0.pointId == pointID',
                       'guard context == current else { return nil }']:
            self.assertIn(marker, self.core)
        self.assertIn('CityPointSelection(pointID: id, rendered: rendered, current: reader.pointMapContext)', self.view)
        self.assertIn('selection?.point(in: reader.pointMapContext)', self.view)
        self.assertIn('Button { select(point.pointId, rendered: context) }', self.view)

    def test_dismiss_refresh_and_disappear_invalidate_old_display_actions(self):
        for marker in ['public let id = UUID()', 'private let context: CityPointMapContext']:
            self.assertIn(marker, self.core)
        for marker in ['selection?.id == renderedSelection.id',
                       'renderedSelection.point(in: reader.pointMapContext) != nil',
                       '.onChange(of: reader.pointMapContext) { _, _ in selection = nil }',
                       '.onDisappear { visible = false; selection = nil; reader.cancel() }',
                       'Button("action.retry") { selection = nil; reader.cancel(); readRequest = UUID() }']:
            self.assertIn(marker, self.view)

    def test_card_and_list_use_exact_title_own_flag_and_accessible_selected_shape(self):
        for marker in ['Text(verbatim: point.title)', 'Text(ownStatus(point))', 'symbol(point)',
                       'city.read.point.card.', 'city.read.point.select.', 'city.read.points.list',
                       'QuestifyMapPinSymbol(symbol: symbol(point), selected:', '.isSelected',
                       '.fixedSize(horizontal: false, vertical: true)', 'minHeight: 44',
                       '.accessibilityHint(Text("city.read.point.selectHint"))']:
            self.assertIn(marker, self.view)
        self.assertIn('point.mine ? "city.read.point.mine" : "city.read.point.notMine"', self.view)
        self.assertIn('if context.points.isEmpty { Text("city.read.points.empty") }', self.view)
        self.assertIn('else { Text("city.read.points.unavailable") }', self.view)

    def test_no_network_location_persistence_or_gameplay_actions_added(self):
        for source in [self.core, self.view]:
            for denied in ['URLSession', 'HTTPTransport', 'CLLocationManager', 'UserAnnotation',
                           'requestWhenInUseAuthorization', 'UserDefaults', 'Keychain', 'POST',
                           'capture', 'reward', 'wallet', 'settlement']:
                self.assertNotIn(denied, source)
        root = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.assertEqual(root.count('cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil }'), 2)

    def test_new_strings_are_complete_bilingual_and_generated_source_is_wired(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['city.read.point.notMine', 'city.read.point.selected', 'city.read.point.readOnly',
                    'city.read.point.clear', 'city.read.points.list', 'city.read.point.selectHint']:
            for language in ['en', 'zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][language]['stringUnit']['value'])
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        self.assertIn('Core/CityPointSelection.swift', project)

    def test_swift_tests_cover_real_reader_fences_and_presentation_identity(self):
        tests = (ROOT / 'Tests/CoreTests/CityPointSelectionTests.swift').read_text()
        for marker in ['testSameNameAndCoincidentCoordinatesRequireExactCanonicalID',
                       'testExactSnapshotAndEveryBoardMembershipRevisionFieldFenceSelection',
                       'testReplacingRemovingOrReorderingProjectionRejectsOldTapAndCard',
                       'testNewReadOrReaderRejectsIdenticalProjectionAndSameID',
                       'testUnavailableAndVerifiedEmptyAreNeverFabricatedSelections',
                       'testDuplicateInvalidOversizedAndUnverifiedOwnStatusProjectionsFailClosed',
                       'testReselectingSamePointHasNewDismissalIdentity',
                       'testDensityCountsOnlySuppliedCanonicalPointsWithoutCollapsingIdentity']:
            self.assertIn(marker, tests)
        app = (ROOT / 'Tests/AppUnitTests/CityPlayerReadCompositionTests.swift').read_text()
        for marker in ['testPointSelectionRechecksAccountRoleSessionAndLeaseBeforeCardOrTap',
                       'testPointSelectionRefreshLoadingAndUnavailableStatesDropOldProjection',
                       'testPointSelectionAcrossDifferentReadersNeverReusesIdenticalSnapshot']:
            self.assertIn(marker, app)

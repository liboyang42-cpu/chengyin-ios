"""Bounded source contracts, not Swift compilation or navigation/runtime tests."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class RoamHistoryLiveEntryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.view = (ROOT / 'App/RoamHistoryViews.swift').read_text()
        cls.hub = (ROOT / 'App/RoamExperienceHubView.swift').read_text()
        cls.history = cls.view.split('@MainActor struct RoamHistoryView: View {', 1)[1].split('/// This only selects', 1)[0]
        cls.owner = cls.view.split('struct RoamHistoryLiveOwner:', 1)[1].split('@MainActor struct RoamHistoryLiveEntry', 1)[0]
        cls.entry = cls.view.split('@MainActor struct RoamHistoryLiveEntry {', 1)[1].split('@MainActor struct RoamHistoryDetailView:', 1)[0]

    def test_only_supplied_destination_is_forwarded_and_missing_provider_stays_absent(self):
        self.assertIn('RoamHistoryView(reader: reader, liveDestination: liveDestination)', self.hub)
        self.assertIn('var liveDestination: (() -> AnyView)? = nil', self.history)
        for token in ['RoamLiveSessionController(', 'RoamLiveSessionView(', 'RoamLivePreparationView(', 'makeRoamLiveSessionController']:
            self.assertNotIn(token, self.view)

    def test_cta_is_inside_successfully_loaded_empty_branch_only(self):
        start = self.history.index('else if records.isEmpty {')
        button = self.history.index('Button("roam.experience.live"')
        nonempty = self.history.index('let summary = RoamHistorySummary(records)')
        self.assertLess(self.history.index('if let error {'), start)
        self.assertLess(self.history.index('else if !loaded {'), start)
        self.assertLess(start, button); self.assertLess(button, nonempty)
        self.assertIn('liveEntry.canOpen(reader: reader, hasDestination: liveDestination != nil)', self.history)

    def test_destination_factory_is_only_in_bound_navigation_destination(self):
        self.assertEqual(self.history.count('liveDestination()'), 1)
        navigation = self.history.split('.navigationDestination(item: $liveEntry.target)', 1)[1]
        self.assertIn('if liveEntry.matches(target, reader: reader, hasDestination: liveDestination != nil), let liveDestination {', navigation)
        self.assertIn('liveDestination()', navigation)
        self.assertIn('let presentationID = liveEntry.presentationID', self.history)
        self.assertIn('liveEntry.activate(reader: reader, hasDestination: liveDestination != nil, presentationID: presentationID)', self.history)

    def test_only_successful_same_owner_receipt_admits_empty_entry(self):
        load = self.history.split('private func load()', 1)[1]
        self.assertLess(load.index('let snapshot = liveEntry.beginRead(reader: reader)'), load.index('try reader.history()'))
        self.assertLess(load.index('try reader.history()'), load.index('liveEntry.acceptRead(isEmpty: records.isEmpty'))
        self.assertNotIn('acceptRead', load.split('catch {', 1)[1])
        self.assertIn('successfulEmptyRead = isEmpty && owner == snapshot && snapshot == RoamHistoryLiveOwner(reader: reader)', self.entry)

    def test_identity_uses_exact_storage_scope_bytes_reader_and_epoch(self):
        for token in ['readerID = ObjectIdentifier(reader)', 'scopeKey = identity?.scope.storageKey', 'epoch = identity?.epoch', 'isConfigured = reader.isConfigured', 'scopeKey != nil && isConfigured']:
            self.assertIn(token, self.owner)
        self.assertIn('.task(id: RoamHistoryLiveOwner(reader: reader)) { load() }', self.history)
        self.assertIn('.onChange(of: RoamHistoryLiveOwner(reader: reader))', self.history)

    def test_tap_and_destination_have_independent_current_owner_guards(self):
        for token in ['visible && target == nil && hasDestination && successfulEmptyRead', 'owner?.isAuthorized == true', 'owner == RoamHistoryLiveOwner(reader: reader)', 'self.presentationID == presentationID', 'self.target == target && hasDestination && target.owner.isAuthorized', 'target.owner == RoamHistoryLiveOwner(reader: reader)']:
            self.assertIn(token, self.entry)

    def test_origin_disappearance_retires_callbacks_without_popping_push(self):
        disappear = self.entry.split('mutating func disappear() {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('visible = false; presentationID = UUID()', disappear)
        self.assertNotIn('target = nil', disappear)
        self.assertIn('.onAppear { liveEntry.appear() }', self.history)
        self.assertIn('.onDisappear { liveEntry.disappear() }', self.history)
        self.assertIn('let id = UUID()', self.entry)
        self.assertIn('var target: Target?', self.entry)

    def test_replacement_logout_provider_loss_and_new_read_invalidate_selection(self):
        self.assertIn('if owner != RoamHistoryLiveOwner(reader: reader) || !hasDestination { invalidate() }', self.entry)
        self.assertIn('target = nil; owner = nil; successfulEmptyRead = false; presentationID = UUID()', self.entry)
        self.assertIn('.onChange(of: liveDestination != nil)', self.history)
        begin = self.entry.split('mutating func beginRead', 1)[1].split('mutating func acceptRead', 1)[0]
        self.assertIn('invalidate()', begin)

    def test_no_location_network_session_or_journal_effect_is_added(self):
        for token in ['CLLocationManager', 'requestWhenInUseAuthorization', 'requestAlwaysAuthorization', 'URLSession', 'api/', 'owner.start(', 'owner.resume(', 'owner.recover(', 'journal.', 'readRecovery', 'validRecovery', 'UserDefaults', 'Task {', 'RoamLiveService(']:
            self.assertNotIn(token, self.view)
        self.assertEqual(self.history.count('try reader.history()'), 1)

    def test_prior_record_detail_navigation_statistics_and_share_remain(self):
        for token in ['RoamHistoryDetailView(reader: reader, timestamp: record.ts)', 'RoamHistorySummary(records)', 'RoamRouteSketchView(record: record)', 'RoamRecordedStats(record: record)', 'RoamExperienceIssue(error: error, retry: load)']:
            self.assertIn(token, self.history)
        self.assertIn('RoamHistoryShareView(record: record)', self.view)


if __name__ == '__main__':
    unittest.main()

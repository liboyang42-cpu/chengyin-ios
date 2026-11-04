#!/usr/bin/env python3
"""Focused source/catalog regressions. Does NOT execute Swift, UI, OS location or HTTP."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import unittest

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
args, _ = parser.parse_known_args()
ROOT = args.root
CORE = (ROOT / 'Core/PersonalLocationShareCoordinator.swift').read_text()
VIEW = (ROOT / 'App/PersonalLocationShareView.swift').read_text()
HOST = (ROOT / 'App/PersonalLocationShareHost.swift').read_text()
PROFILE = (ROOT / 'App/SocialPublicProfileView.swift').read_text()
CATALOG = json.loads((ROOT / 'Resources/PersonalLocationShare.xcstrings').read_text())['strings']


def section(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


class RecoveryPresentationSourceChecks(unittest.TestCase):
    def test_journal_evidence_is_observable_and_separate(self):
        self.assertIn('public private(set) var journalReadState: JournalReadState = .unread', CORE)
        self.assertIn('journalReadState = .unavailable; journalHealthy = false', CORE)
        management = section(CORE, 'public func openManagement()', 'private func invalidateConfirmation')
        self.assertNotIn('journalReadState =', management)
        self.assertNotIn('journalHealthy =', management)

    def test_only_verified_empty_journal_gets_empty_copy(self):
        self.assertIn('if coordinator.originalRequestsAreVerifiedEmpty', VIEW)
        self.assertNotIn('if coordinator.pending.isEmpty { Text(localized("personalLocationShare.emptyRequests")) }', VIEW)
        self.assertIn('journalReadState == .readable && !hasUnpersistedStopIntent && pending.isEmpty', CORE)

    def test_recovery_warning_is_not_the_overwritable_global_message(self):
        self.assertIn('coordinator.journalReadState == .unavailable', VIEW)
        self.assertIn('personalLocationShare.journal.unavailable', VIEW)
        self.assertIn('coordinator.hasUnpersistedStopIntent', VIEW)
        self.assertIn('personalLocationShare.stopUnpersisted', VIEW)

    def test_read_only_restore_keeps_original_stop_projection(self):
        restore = section(CORE, 'public func restoreOriginalRequests()', 'public func readback(')
        self.assertIn('stopFence.contains(record.id) || unpersistedStopKeys.contains(record.id)', restore)
        self.assertIn('record.stopRequested = true', restore)
        for forbidden in ['service.create(', 'journal.put(', 'journal.remove(', 'providerFactory.make(', 'UUID()']:
            self.assertNotIn(forbidden, restore)
        self.assertIn('await readback(requestKey: record.id)', restore)

    def test_new_create_and_confirmation_locks_are_retained(self):
        gate = section(CORE, 'public var canConfirm:', 'public var visibleLocations:')
        for required in ['journalHealthy', 'unpersistedStopKeys.isEmpty', 'providerIsConnected', 'pending.isEmpty', 'acknowledgements == Set(PersonalLocationShareDisclosure.allCases)']:
            self.assertIn(required, gate)
        self.assertLess(CORE.index('try journal.put(record, scope: scope) // Durable original key'), CORE.index('receipt = try await service.create(request)'))

    def test_stop_persists_before_original_key_revoke(self):
        stop = section(CORE, 'public func stop(requestKey:', 'private func persistStop(')
        self.assertLess(stop.index('stopLocalPublisher()'), stop.index('try persistStop('))
        self.assertLess(stop.index('try persistStop('), stop.index('retryStop(requestKey: requestKey)'))
        self.assertIn('service.revoke(requestKey: requestKey)', CORE)

    def test_current_reads_have_independent_loading_and_failure(self):
        for field in ['ownedReadState', 'receivedReadState']:
            for state in ['loading', 'loaded', 'unavailable']:
                self.assertIn(field + ' = .' + state, CORE)
            self.assertIn('currentReadStatus(coordinator.' + field + ')', VIEW)
        self.assertIn('readRevision == managementReadRevision', CORE)
        self.assertIn('if coordinator.ownedReadState == .loaded && coordinator.ownedGrants.isEmpty', VIEW)

    def test_dynamic_suffixes_are_translated_not_exact_match_fallback(self):
        suffixes = re.findall(r'message \+= "([^"]+)"', CORE)
        self.assertGreaterEqual(len(suffixes), 4)
        for suffix in set(suffixes):
            self.assertRegex(CORE, re.escape('("' + suffix + '", "personalLocationShare.status.'))
        self.assertIn('base.hasSuffix($0.0)', CORE)
        self.assertIn('coordinator.messageParts.map', VIEW)

    def test_parameterized_http_rejection_has_catalog_entry(self):
        self.assertIn('key: "personalLocationShare.status.authorizationRejected", arguments: [status]', CORE)
        for locale in ['en', 'zh-Hans']:
            value = CATALOG['personalLocationShare.status.authorizationRejected']['localizations'][locale]['stringUnit']['value']
            self.assertEqual(value.count('%@'), 1)

    def test_static_statuses_use_existing_37_keys(self):
        for n in range(1, 38):
            key = f'personalLocationShare.status.{n:02d}'
            self.assertIn('key = "' + key + '"', CORE)
            self.assertIn(key, CATALOG)
        self.assertIn('key: nil, arguments: [], fallback: base', CORE)

    def test_all_referenced_dedicated_keys_are_bilingual(self):
        referenced = set(re.findall(r'"(personalLocationShare\.[A-Za-z0-9.]+)"', CORE + VIEW + HOST + PROFILE))
        # Accessibility IDs are stable selectors, not visible strings.
        selectors = set(re.findall(r'accessibilityIdentifier\("([^\"]+)"', CORE + VIEW + HOST + PROFILE))
        keys = referenced - selectors
        self.assertFalse(keys - CATALOG.keys(), "Missing dedicated catalog keys")
        self.assertGreaterEqual(len(keys), 110)
        for key in keys:
            for locale in ['en', 'zh-Hans']:
                value = CATALOG[key]['localizations'][locale]['stringUnit']['value']
                self.assertTrue(value.strip(), (key, locale))
            en = CATALOG[key]['localizations']['en']['stringUnit']['value']
            zh = CATALOG[key]['localizations']['zh-Hans']['stringUnit']['value']
            self.assertEqual(re.findall(r'%[0-9$]*[@diuf]', en), re.findall(r'%[0-9$]*[@diuf]', zh), key)

    def test_unavailable_and_profile_entry_use_dedicated_catalog(self):
        entry = HOST.split('@MainActor struct PersonalLocationShareEntry:', 1)[1]
        self.assertNotIn('ContentUnavailableView("尚无当前有效、已批准的共享政策，所有共享选择均不可用。"', entry)
        self.assertIn('personalLocationShare.unavailable.title', entry)
        self.assertIn('personalLocationShare.unavailable.description', entry)
        self.assertIn('ScrollView {', entry)
        self.assertNotIn('Label("向此人共享位置"', PROFILE)
        self.assertIn('Text("personalLocationShare.title.person", tableName: "PersonalLocationShare")', PROFILE)

    def test_native_safe_area_dynamic_type_and_navigation_are_retained(self):
        self.assertIn('Form {', VIEW)
        self.assertIn('.navigationTitle(', VIEW)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', VIEW)
        self.assertIn('.accessibilityHint(', VIEW)
        for forbidden in ['.ignoresSafeArea(', '.lineLimit(1)', '.minimumScaleFactor(', '.frame(height:']:
            self.assertNotIn(forbidden, VIEW)

    def test_explicit_final_confirmation_and_disappear_retirement_remain(self):
        for required in ['.confirmationDialog(', 'coordinator.confirmStart(ticket: ticket)', 'coordinator.confirmationEntryDisappeared(presentationId: presentationId)', 'ticket.allowsFirstPermissionRequest == allowsFirstPermissionRequest']:
            self.assertIn(required, VIEW)
        self.assertIn('if let recipientId', VIEW)
        self.assertIn('else { await coordinator.openManagement() }', VIEW)

    def test_original_98_catalog_entries_are_unchanged(self):
        keys = ORIGINAL_KEYS
        normalized = json.dumps({key: CATALOG[key] for key in keys}, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
        self.assertEqual(hashlib.sha256(normalized).hexdigest(), ORIGINAL_SHA256)


# Exact baseline key set and value digest; adding new translations must not replace the original table.
ORIGINAL_KEYS = ['personalLocationShare.title.management', 'personalLocationShare.title.person', 'personalLocationShare.disclosure.summary', 'personalLocationShare.unconfigured', 'personalLocationShare.recipient', 'personalLocationShare.memberID', 'personalLocationShare.eligibilityNotice', 'personalLocationShare.recheck', 'personalLocationShare.choices', 'personalLocationShare.precision', 'personalLocationShare.choose', 'personalLocationShare.exact', 'personalLocationShare.coarse', 'personalLocationShare.duration', 'personalLocationShare.precisionNotice', 'personalLocationShare.acknowledgements', 'personalLocationShare.firstPermission', 'personalLocationShare.start', 'personalLocationShare.requests', 'personalLocationShare.emptyRequests', 'personalLocationShare.readRequest', 'personalLocationShare.retryStop', 'personalLocationShare.stop', 'personalLocationShare.restore', 'personalLocationShare.grants', 'personalLocationShare.refreshManagement', 'personalLocationShare.stopGrant', 'personalLocationShare.received', 'personalLocationShare.refreshReceived', 'personalLocationShare.emptyLocations', 'personalLocationShare.coarseObservation', 'personalLocationShare.exactObservation', 'personalLocationShare.stale', 'personalLocationShare.snapshot', 'personalLocationShare.confirmFirstPermission', 'personalLocationShare.confirmExistingPermission', 'personalLocationShare.cancel', 'personalLocationShare.state.creating', 'personalLocationShare.state.active', 'personalLocationShare.state.stopPending', 'personalLocationShare.state.stopped', 'personalLocationShare.state.unknown', 'personalLocationShare.disclosure.audience', 'personalLocationShare.disclosure.precision', 'personalLocationShare.disclosure.duration', 'personalLocationShare.disclosure.foreground', 'personalLocationShare.disclosure.stop', 'personalLocationShare.disclosure.recall', 'personalLocationShare.seconds', 'personalLocationShare.policy', 'personalLocationShare.recipientValue', 'personalLocationShare.requestValue', 'personalLocationShare.recipientGrant', 'personalLocationShare.expires', 'personalLocationShare.grantStatus', 'personalLocationShare.owner', 'personalLocationShare.coordinates', 'personalLocationShare.observed', 'personalLocationShare.grantExpires', 'personalLocationShare.confirmTitle', 'personalLocationShare.confirmationSummary', 'personalLocationShare.status.01', 'personalLocationShare.status.02', 'personalLocationShare.status.03', 'personalLocationShare.status.04', 'personalLocationShare.status.05', 'personalLocationShare.status.06', 'personalLocationShare.status.07', 'personalLocationShare.status.08', 'personalLocationShare.status.09', 'personalLocationShare.status.10', 'personalLocationShare.status.11', 'personalLocationShare.status.12', 'personalLocationShare.status.13', 'personalLocationShare.status.14', 'personalLocationShare.status.15', 'personalLocationShare.status.16', 'personalLocationShare.status.17', 'personalLocationShare.status.18', 'personalLocationShare.status.19', 'personalLocationShare.status.20', 'personalLocationShare.status.21', 'personalLocationShare.status.22', 'personalLocationShare.status.23', 'personalLocationShare.status.24', 'personalLocationShare.status.25', 'personalLocationShare.status.26', 'personalLocationShare.status.27', 'personalLocationShare.status.28', 'personalLocationShare.status.29', 'personalLocationShare.status.30', 'personalLocationShare.status.31', 'personalLocationShare.status.32', 'personalLocationShare.status.33', 'personalLocationShare.status.34', 'personalLocationShare.status.35', 'personalLocationShare.status.36', 'personalLocationShare.status.37']
ORIGINAL_SHA256 = 'c4404192f927d850bc9026c61f03764d729aa3d1164a7b9cf50db59eb9204f5a'

if __name__ == '__main__':
    print('SOURCE/CATALOG ONLY — Swift, XCTest, App, visual/VoiceOver, OS location and HTTP are NOT_RUN.', flush=True)
    unittest.main(argv=[__file__], verbosity=2)

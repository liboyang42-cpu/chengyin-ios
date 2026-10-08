"""Supplementary source contracts only. They do not compile or execute Swift."""
import hashlib
import json
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = 'Core/MerchantCustomerDetailPresentation.swift'
APP = 'App/MerchantCustomerDetailSections.swift'

class MerchantCustomerDetailContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_existing_post_reader_and_identity_are_reused(self):
        query = self.read('Core/MerchantBusinessQuery.swift')
        self.assertIn('case .customer(let id): return .empty("api/merchant/crm/customers/\\(id.rawValue)/detail")', query)
        self.assertIn('case .customers, .customer: return ["merchant:crm:read"]', query)
        core = self.read(CORE)
        self.assertIn('summary.mbInt("customerMemberId", minimum: 1) == customerID.rawValue', core)
        self.assertIn('try access.require(query.permissions)', self.read('Core/MerchantBusinessService.swift'))

    def test_only_registration_facts_group_and_history_never_drops(self):
        core = self.read(CORE)
        self.assertIn('^registration-[0-9]+$', core)
        self.assertIn('let key = isRegistration ? "registration:" + record.id : "event:\\(index)"', core)
        self.assertIn('groups[key, default: []].append(event)', core)
        self.assertIn('guard historyKeys.insert(record.id).inserted', core)
        self.assertIn('other.append(event)', core)
        self.assertIn('case note = "NOTE", correction = "NOTE_CORRECTION", campaign = "CAMPAIGN"', core)
        self.assertNotIn('REFUND_PROCESSING', core)
        self.assertNotIn('REFUND_REQUESTED', core)

    def test_latest_requires_all_times_known_and_no_tie(self):
        core = self.read(CORE)
        self.assertIn('events.allSatisfy({ $0.occurredAt != nil })', core)
        self.assertIn('events.filter({ $0.occurredAt == instant }).count == 1', core)
        self.assertIn('case let (a?, b?) where a != b: return a > b', core)
        self.assertIn('default: return lhs.id < rhs.id', core)
        self.assertNotIn('Date()', core)
        self.assertNotIn('timeIntervalSinceNow', core)

    def test_exact_payload_survives_and_actions_use_original_history(self):
        document = self.read('Core/MerchantBusinessDocuments.swift')
        self.assertIn('self.query = query; self.payload = payload', document)
        self.assertIn('let detail = try MerchantCustomerDetailPresentation(customerID: id, payload: payload)', document)
        self.assertIn('try .init("timeline", rows: detail.history.map(\\.record))', document)
        self.assertIn('actions(event.record)', self.read(APP))
        self.assertIn('actions(tag)', self.read(APP))

    def test_customer_ui_is_under_current_snapshot_and_all_existing_fences(self):
        page = self.read('App/MerchantBusinessViews.swift')
        marker = 'if let snapshot = state.snapshot, state.isCurrent {'
        component = 'MerchantCustomerDetailSections(detail: detail, access: snapshot.access)'
        self.assertLess(page.index(marker), page.index(component))
        self.assertIn('if case .customer = query, let detail = snapshot.document.customerDetail', page)
        self.assertIn('rowActions(row, access: snapshot.access)', page)
        self.assertIn('.onChange(of: reader.authorizationGeneration)', page)
        self.assertIn('.onDisappear { editor = nil; pendingMutation = nil; model.invalidate() }', page)
        self.assertIn('authorization == coordinator.reader.authorizationGeneration', page)

    def test_sensitive_money_requires_both_current_permissions(self):
        app = self.read(APP)
        self.assertIn('var canRead: Bool { access.allows("merchant:crm:read") }', app)
        self.assertIn('guard canRead, access.allows("merchant:crm:sensitive:read")', app)
        self.assertIn('if canRead {', app)
        self.assertIn('amount.raw != nil', app)
        self.assertNotIn('phone', app.replace('phoneTimeZone', 'zone'))

    def test_dynamic_phone_zone_and_refund_time_boundary(self):
        core, app = self.read(CORE), self.read(APP)
        self.assertIn('MerchantAftercareTime.parse(text)', core)
        self.assertIn('OrderLifecycleTime.date(text)', core)
        self.assertIn('MerchantAftercareTime.event(date, phoneTimeZone: phoneTimeZone)', core)
        self.assertIn('@State private var phoneTimeZone = TimeZone.current', app)
        self.assertIn('.NSSystemTimeZoneDidChange', app)
        self.assertIn('merchant.customerDetail.recordTime', app)
        self.assertIn('merchant.customerDetail.refundTimeBoundary', app)
        self.assertIn('if latest.kind == .refunded', app)
        self.assertNotIn('refundCompletedAt', core)

    def test_projection_has_no_new_transport_persistence_or_business_writes(self):
        for source in [self.read(CORE), self.read(APP)]:
            for forbidden in ['URLSession', 'URLRequest', 'UserDefaults', 'FileManager', 'UIPasteboard', 'print(', 'Logger', '.execute(', '.reserve(', '.confirm(', '.task(']:
                self.assertNotIn(forbidden, source)
        self.assertNotIn('api/', self.read(CORE) + self.read(APP))

    def test_bilingual_keys_empty_states_and_accessibility(self):
        fragment = json.loads(self.read('Resources/MerchantCustomerDetailLocalizations.fragment.json'))
        source = self.read(APP) + self.read(CORE)
        source = re.sub(r'\.accessibilityIdentifier\([^\n]*', '', source)
        for key in set(re.findall(r'"(merchant\.customerDetail\.[A-Za-z.]+)"', source)):
            if key.endswith('.'): continue
            self.assertIn(key, fragment)
        for code in ['REGISTERED', 'ARRIVED', 'REFUNDED', 'NOTE', 'NOTE_CORRECTION', 'CAMPAIGN']:
            self.assertIn('merchant.customerDetail.event.' + code, fragment)
        for row in fragment.values():
            self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'})
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(row['localizations'][locale]['stringUnit']['value'].strip())
        app = self.read(APP)
        for token in ['.fixedSize(horizontal: false, vertical: true)', '.accessibilityElement(children: .combine)',
                      '.accessibilityElement(children: .contain)', '.frame(minHeight: 44)',
                      'merchant.customerDetail.participationEmpty', 'merchant.customerDetail.historyEmpty']:
            self.assertIn(token, app)

    def test_authored_swift_tests_cover_source_projection_and_lifetime(self):
        core = self.read('Tests/CoreTests/MerchantCustomerDetailPresentationTests.swift')
        app = self.read('Tests/AppUnitTests/MerchantCustomerDetailSectionsTests.swift')
        for token in ['testOnlyRegistrationKeysGroupAndUseAbsoluteInstants', 'testInvalidOrMissingTimeNeverProducesLatestClaim',
                      'testTiedInstantKeepsStableFactsWithoutChoosingLatest', 'testDocumentRetainsExactRawPayloadAndActionHistory',
                      'testPhoneZoneCrossDayAndDSTDoNotChangeEventInstant', 'testDuplicateHistoryIDsAndUnknownKindsFailClosed']:
            self.assertIn('func ' + token, core)
        for token in ['testReadOnlyPermissionDoesNotExposeReturnedSensitiveAmount',
                      'testLateAccountAndAuthorizationResponsesCannotRepopulateCustomer',
                      'testDismissalAndCancelledReadCannotRepopulateCustomer',
                      'testOlderReadCannotReplaceRefreshedCustomerProjection',
                      'testPermissionFailureOnRefreshClearsPreviousCustomer']:
            self.assertIn('func ' + token, app)

    def test_optional_verified_source_blobs_and_refund_semantics(self):
        value = os.environ.get('CHENGYIN_CUSTOMER_DETAIL_EVIDENCE')
        if not value:
            self.skipTest('NOT_RUN: private source evidence directory not supplied')
        root = Path(value)
        expected = {
            'detail-index.js': 'ba72ce2e8a1617803fa9ebfb31b7782a000d9e7e',
            'detail-index.wxml': '220d3c0ea70cff5dd2e615113945b3f3e8fd35c5',
            'detail-view-model.js': '54c03e023837eb768527589a041509a0f1b5730f',
            'ApiMerchantCrmController.java': '61ab0645b60800f9b8edf7f61fd5690b3b7c33f2',
            'MerchantCrmAppServiceImpl.java': 'e83de32e964301fb2c5395fdbeb012a578c12e58',
            'MerchantCrmTimelineItemVO.java': 'd0efc410ae73e12fd9794e43d1299edbcc9e0be6',
            'MerchantCrmAppMapper.xml': '1b95e06b64fffae2f487b1c548480271b81ea175',
            'datetime.js': '2163e57af3d7d8cc47b879970a2e96d3c4371ed7',
        }
        for filename, sha in expected.items():
            data = (root / filename).read_bytes()
            self.assertEqual(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(), sha, filename)
        controller = (root / 'ApiMerchantCrmController.java').read_text()
        self.assertIn('@PostMapping("/customers/{customerMemberId}/detail")', controller)
        mapper = (root / 'MerchantCrmAppMapper.xml').read_text().split('<select id="selectOwnedInteractions"', 1)[1].split('</select>', 1)[0]
        self.assertIn("case when r.payment_status = 4 then 'REFUNDED'", mapper)
        self.assertIn('then r.verification_time else r.create_time end as occurred_at', mapper)
        service = (root / 'MerchantCrmAppServiceImpl.java').read_text()
        self.assertIn('summary.setPaidAmount(null)', service)
        self.assertIn('TIMELINE_LIMIT = 50', service)
        self.assertIn('out.setKey("registration-" + row.getRegistrationId())', service)
        vm = (root / 'detail-view-model.js').read_text()
        self.assertIn('function buildParticipation(timeline)', vm)
        self.assertIn('function buildHistory(timeline)', vm)
        self.assertIn('function latestNoteText(timeline)', vm)

if __name__ == '__main__': unittest.main()

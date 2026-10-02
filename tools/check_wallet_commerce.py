#!/usr/bin/env python3
"""Source/structure assertions only. Never runs Swift, backend or financial operations."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'app-audit/lib'

class WalletSourceChecks(unittest.TestCase):
    def setUp(self):
        self.service = (ROOT/'Core/WalletCommerceService.swift').read_text()
        self.safety = (ROOT/'Core/WalletCommerceSafety.swift').read_text()
        self.views = (ROOT/'App/WalletCommerceViews.swift').read_text()
        self.contracts = (ROOT/'Core/WalletCommerceContracts.swift').read_text()
    def test_all_native_paths_have_source_evidence(self):
        source = '\n'.join((SOURCE/f'data/api/{name}_api.dart').read_text() for name in ['asset','points','mall','withdrawal','registration'])
        paths = set(re.findall(r'"(api/[^"\s]+)"', self.service+self.safety))
        self.assertEqual(len(paths), 15)
        for path in paths: self.assertIn('/'+path, source)
    def test_withdrawal_source_is_read_only(self):
        source=(SOURCE/'data/api/withdrawal_api.dart').read_text()
        self.assertIn('create` / `preflight',source)
        self.assertNotRegex(self.service+self.safety,r'api/withdrawal/(create|preflight|submit|transfer)')
        self.assertIn('body: false', self.service)
    def test_page_contracts_stay_separate(self):
        self.assertIn('path = "api/balance/list"; paged = false',self.service)
        self.assertIn('path = "api/points/list"; paged = false',self.service)
        self.assertIn('path = "api/user/points/list"; paged = true',self.service)
        self.assertIn('path = "api/user/balance/list"; paged = true',self.service)
        self.assertIn('fields["eventType"] = filter.rawValue',self.service)
        self.assertIn('pageNum', (SOURCE/'data/api/points_api.dart').read_text())
    def test_stages_are_json(self):
        self.assertIn('path: "api/wallet/stages", fields: [:], token: token, json: true',self.service)
        self.assertIn('application/json',self.service)
        self.assertIn('Data("{}".utf8)',self.service)
    def test_unknown_money_is_nullable(self):
        for declaration in ['changeBalance: WalletAmount?', 'price: WalletAmount?', 'totalAmount: WalletAmount?', 'currency: String?', 'pointBalance: WalletAmount?']:
            self.assertIn(declaration,self.contracts)
        self.assertNotIn('price ?? 0',self.contracts+self.views)
    def test_locks_before_dispatch_and_no_pii_in_journal(self):
        self.assertLess(self.safety.index('try journal.write(pending)'),self.safety.index('transport.send(request)'))
        self.assertIn('guard enableReviewedWrites else',self.safety)
        self.assertIn('enableReviewedWrites: Bool = false',self.safety)
        self.assertIn('snapshot.scope == scope',self.safety)
        self.assertIn('snapshot.cartIDs == ids',self.safety)
        self.assertIn('currentScope() == review.scope',self.safety)
        self.assertIn('OperationPendingRecord(ownerKey: review.scope.owner, targetKey: lockTarget)',self.safety)
        self.assertNotRegex(self.safety, r'print\(|NSLog\(|logger\.')
    def test_no_live_factory_or_root_navigation_mutation(self):
        self.assertNotIn('URLSession', self.service+self.safety)
        self.assertIn('service: WalletCommerceService? = nil',self.safety)
        self.assertIn('public var mall = false',self.safety)
        self.assertNotIn('execute(', self.views)
    def test_bilingual_catalog_covers_literal_and_dynamic_keys(self):
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        keys=set(re.findall(r'"(wallet\.[A-Za-z][A-Za-z0-9.]*)"',self.views+self.contracts))
        keys={k for k in keys if not k.endswith('.') and k not in {'wallet.issue','wallet.dormant','wallet.previewOnly'}}
        # Identifier keys above also have ordinary translations except issue.
        for key in keys:
            self.assertIn(key,catalog)
        for key in ['wallet.sort.'+str(i) for i in range(5)]+['wallet.direction.'+s for s in ['income','expense','unknown']]:
            self.assertIn(key,catalog)
        for row in catalog.values(): self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
    def test_privacy_and_accessibility(self):
        self.assertIn('return value.count > 4 ? "•••• "',self.contracts)
        self.assertNotIn('public let bankAccount',self.contracts)
        self.assertNotIn('public let fullName',self.contracts)
        self.assertIn('accessibilityElement(children: .combine)',self.views)
        self.assertIn('frame(minHeight: 44)',self.views)
        self.assertIn('wallet.direction.',self.views)
    def test_existing_task_rule_filter_is_preserved(self):
        self.assertIn('status == 1 && eventType != 14',self.contracts)
        self.assertIn('api/points/result_list',self.service)
    def test_synthetic_transport_has_no_mutation_success(self):
        fake=(ROOT/'Core/WalletCommerceSyntheticFixtures.swift').read_text()
        self.assertNotIn('case "/api/cart/order/settlement"',fake)
        self.assertNotIn('URLSession',fake)
        self.assertIn('default: throw APIError.invalidRequest',fake)

if __name__ == '__main__': unittest.main(verbosity=2)

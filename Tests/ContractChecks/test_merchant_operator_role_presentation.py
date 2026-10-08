"""Offline source contracts only: no Swift compilation, UI runtime or service calls."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = 'Core/MerchantOperatorRolePresentation.swift'
APP = 'App/MerchantOperatorRolePermissionSection.swift'
FRAGMENT = 'Resources/MerchantOperatorRoleLocalizations.fragment.json'
SOURCE_CODES = {
    'merchant:basic:read', 'merchant:profile:write', 'merchant:project:manage',
    'merchant:verify', 'merchant:verify:record:read', 'merchant:order:read',
    'merchant:crm:read', 'merchant:crm:sensitive:read', 'merchant:crm:segment',
    'merchant:crm:export', 'merchant:finance:read', 'merchant:aftercare:read',
    'merchant:aftercare:respond', 'merchant:aftercare:decide', 'merchant:aftercare:evidence',
    'merchant:marketing:read', 'merchant:marketing:write', 'merchant:coupon:manage',
    'merchant:coop:manage', 'merchant:operator:manage',
}


class MerchantOperatorRolePresentationContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_all_twenty_exact_backend_codes_have_labels(self):
        source = self.read(CORE)
        codes = re.findall(r'case \w+ = "(merchant:[^"\n]+)"', source)
        self.assertEqual(len(codes), 20)
        self.assertEqual(set(codes), SOURCE_CODES)

    def test_only_supplied_role_record_permissions_are_projected(self):
        source = self.read(CORE)
        for snippet in ['guard record.kind == .role', 'roleCode = record.id',
                        'try record.fields.mbStrings("permissions")',
                        'MerchantOperatorPermissionDescription(rawValue: $0)',
                        'seen.insert($0).inserted']:
            self.assertIn(snippet, source)
        for forbidden in ['employeeRoles', 'MERCHANT_OWNER', 'permissionsFor',
                          '.lowercased()', 'trimmingCharacters', '.allows(', '.require(']:
            self.assertNotIn(forbidden, source)

    def test_existing_form_uses_exact_selected_server_role(self):
        source = self.read('App/MerchantBusinessEditor.swift')
        self.assertIn('ForEach(snapshot?.roles?.rows ?? []) { item in Text(item.fields.mbText("name") ?? item.id).tag(item.id) }', source)
        self.assertIn('if let selected = snapshot?.roles?.rows.first(where: { $0.id == role })', source)
        self.assertIn('MerchantOperatorRolePermissionSection(role: selected)', source)
        self.assertIn('case .invite: return .inviteOperator(role: role)', source)
        self.assertIn('version: try row.fields.mbInt("version"), role: role)', source)
        self.assertIn('Text("merchant.business.rolesBoundary")', source)

    def test_unknown_codes_show_literal_code_and_explanation(self):
        core, app = self.read(CORE), self.read(APP)
        self.assertIn('description?.titleKey ?? "merchant.operatorRole.unknown.title"', core)
        self.assertIn('description?.detailKey ?? "merchant.operatorRole.unknown.detail"', core)
        self.assertIn('if entry.description == nil', app)
        self.assertIn('permissionCode(entry.code)', app)
        self.assertIn('Text(verbatim: code)', app)
        self.assertIn('merchant.operatorRole.emptyCode', app)

    def test_empty_unavailable_and_refresh_are_honest(self):
        source = self.read(APP)
        self.assertIn('private var presentation: MerchantOperatorRolePresentation? { try? .init(record: role) }', source)
        self.assertIn('presentation.entries.isEmpty', source)
        self.assertIn('merchant.operatorRole.empty', source)
        self.assertIn('merchant.operatorRole.unavailable', source)
        self.assertIn('.id(role.id)', source)
        self.assertNotIn('@State', source)

    def test_accessibility_and_dynamic_type_are_used(self):
        source = self.read(APP)
        for snippet in ['.font(.subheadline.bold())', '.font(.footnote)',
                        '.accessibilityElement(children: .combine)',
                        '.accessibilityIdentifier("merchant.operatorRole.permission." + entry.code)',
                        'DisclosureGroup("merchant.operatorRole.codes")']:
            self.assertIn(snippet, source)
        self.assertNotIn('.lineLimit(', source)
        self.assertNotIn('.frame(height:', source)

    def test_all_generated_and_literal_strings_are_bilingual(self):
        fragment = json.loads(self.read(FRAGMENT))
        self.assertEqual(len(fragment), 47)
        for code in SOURCE_CODES:
            for suffix in ['title', 'detail']:
                self.assertIn('merchant.operatorRole.permission.' + code.removeprefix('merchant:').replace(':', '.') + '.' + suffix, fragment)
        source = re.sub(r'\.accessibilityIdentifier\([^\n]*', '', self.read(APP) + self.read(CORE))
        for key in set(re.findall(r'"(merchant\.operatorRole\.[A-Za-z.]+)"', source)):
            if not key.endswith('.'):
                self.assertIn(key, fragment)
        for key, entry in fragment.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)
            for row in entry['localizations'].values():
                self.assertTrue(row['stringUnit']['value'].strip(), key)

    def test_read_write_sensitive_and_refund_boundaries_are_explicit(self):
        fragment = json.loads(self.read(FRAGMENT))
        def en(suffix):
            return fragment['merchant.operatorRole.' + suffix]['localizations']['en']['stringUnit']['value']
        self.assertIn('separate permission', en('permission.crm.read.detail'))
        self.assertIn('separate consent', en('permission.crm.sensitive.read.detail'))
        self.assertIn('does not authorize payments, transfers or refunds', en('permission.finance.read.detail'))
        self.assertIn('does not execute a refund', en('permission.aftercare.decide.detail'))
        self.assertIn('server', en('scope'))

    def test_no_new_authorization_transport_or_persistence(self):
        source = self.read(CORE) + self.read(APP)
        for forbidden in ['URLSession', 'URLRequest', 'UserDefaults', 'FileManager',
                          'UIPasteboard', '.execute(', '.reserve(', '.confirm(',
                          '.task(', 'api/', 'canExecute', 'currentSession', 'token']:
            self.assertNotIn(forbidden, source)

    def test_runtime_negatives_are_authored_not_claimed_as_run(self):
        source = self.read('Tests/CoreTests/MerchantOperatorRolePresentationTests.swift')
        self.assertEqual(len(re.findall(r'    func test\w+\(', source)), 12)
        for name in ['testDescriptionsMatchOnlyExactCodes',
                     'testEmptyManagerRoleDoesNotInferPresetPermissions',
                     'testSameRoleRefreshDoesNotCacheOldPermissions',
                     'testNonRoleRecordCannotBecomePermissionPresentation',
                     'testSourceDocumentAndMutationRequestRemainUnchanged']:
            self.assertIn('func ' + name, source)


if __name__ == '__main__':
    unittest.main(verbosity=2)

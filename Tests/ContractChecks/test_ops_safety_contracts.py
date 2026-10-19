"""Bounded source contracts for reform plan v9 W01/W09/W11 client hooks.
These do not execute Swift or SwiftUI; they pin default-off and copy boundaries."""
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
OPS = (ROOT / 'Core/OpsDegradedState.swift').read_text()
SAFETY = (ROOT / 'Core/SafetyDisclosure.swift').read_text()
TRAIL = (ROOT / 'Core/OpsAuditTrail.swift').read_text()
VIEWS = (ROOT / 'App/OpsSafetyViews.swift').read_text()
APP = (ROOT / 'App/QuestifyApp.swift').read_text()
CATALOG = json.loads((ROOT / 'Resources/OpsSafety.xcstrings').read_text())['strings']
SOURCES = OPS + SAFETY + TRAIL + VIEWS


class OpsSafetyContracts(unittest.TestCase):
    def test_new_core_types_perform_no_network_or_storage(self):
        for source in (OPS, SAFETY, TRAIL):
            for term in ['URLSession', 'HTTPTransport', 'UserDefaults', 'kSecAttrService', 'FileManager', 'CLLocationManager']:
                self.assertNotIn(term, source)

    def test_not_wired_into_shipped_composition(self):
        for path in ['App/AppCompositionRoot.swift', 'App/AppSession.swift', 'App/RegionalLaunchConfiguration.swift']:
            text = (ROOT / path).read_text()
            for term in ['OpsKillSwitchReadoutDecoder', 'OfflineNodeSafetyDecoder', 'planProposalAIOnly']:
                self.assertNotIn(term, text)

    def test_preserved_services_and_unknown_readouts_are_never_gated(self):
        self.assertIn('if kind == .preservedService { return .preserved }', OPS)
        self.assertIn('case .unknown: missing.append(target.layer)', OPS)
        self.assertIn('return missing.isEmpty ? .proceed : .unverified(missing)', OPS)

    def test_timed_out_write_is_unknown_not_failure(self):
        self.assertIn('case .write: return .writeOutcomeUnknown', OPS)
        self.assertIn('public static let disabled = OpsDeadlinePolicy()!', OPS)

    def test_fixture_is_debug_only(self):
        start = VIEWS.index('#if DEBUG'); self.assertLess(start, VIEWS.index('struct OpsSafetyFixtureHost'))
        debug = APP.index('#if DEBUG'); release = APP.index('#else')
        self.assertTrue(debug < APP.index('--ops-safety-fixture') < release)

    def test_every_referenced_key_is_bilingual(self):
        # Literal keys passed to localized text; accessibility identifiers are not keys.
        keys = set(re.findall(r'(?:opsText|LocalizedStringKey)\("(opsSafety\.[A-Za-z.]+)"', VIEWS))
        keys |= set(re.findall(r'"(opsSafety\.(?:ai|offline|presence)\.[A-Za-z.]+)"', SAFETY))
        keys |= set(re.findall(r'"(opsSafety\.timeout\.[A-Za-z.]+)"', OPS))
        for enum, prefix, source in [('OpsIncidentKind', 'opsSafety.incident.', OPS), ('OpsPreservedAction', 'opsSafety.action.', OPS),
                                     ('AIOutgoingSensitiveKind', 'opsSafety.ai.sensitive.', SAFETY)]:
            body = source.split('public enum ' + enum)[1].split('public var copyKey')[0]
            for line in re.findall(r'case ([a-zA-Z, ]+)', body):
                keys |= {prefix + name.strip() for name in line.split(',')}
        keys = {k for k in keys if not k.endswith('.')}
        missing = sorted(k for k in keys if k not in CATALOG)
        self.assertEqual(missing, [])
        self.assertGreater(len(keys), 40)
        for key, value in CATALOG.items():
            locs = value['localizations']
            self.assertTrue(locs['en']['stringUnit']['value'].strip() and locs['zh-Hans']['stringUnit']['value'].strip(), key)

    def test_copy_promises_no_server_facts(self):
        text = json.dumps(CATALOG, ensure_ascii=False)
        for banned in ['补偿', '退款到账', '分钟内', 'compensat', 'within ', 'refunded', '违规用户', 'cheat']:
            self.assertNotIn(banned, text)

    def test_audit_tool_catalog_is_complete(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/audit_client_ops_surfaces.py'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

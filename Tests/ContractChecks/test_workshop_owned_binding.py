"""Source-only AppSession integration seam; no Apple execution claim."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class WorkshopOwnedBindingContracts(unittest.TestCase):
    def test_binding_retains_and_invalidates_before_replacement(self):
        source=(ROOT/'App/WorkshopOwnedSessionBinding.swift').read_text()
        self.assertIn('ContentDraftContextFence.matches(captured, context)',source)
        self.assertIn('revision == configurationRevision { return }',source)
        self.assertIn('invalidate()\n        captured = context; revision = configurationRevision\n        browser = makeBrowser(context)',source)
        self.assertIn('browser?.invalidate()\n        browser = nil',source)
    def test_no_default_approval_or_requests(self):
        source=(ROOT/'App/WorkshopOwnedSessionBinding.swift').read_text()
        self.assertIn('configurationRevision: UUID? = nil',source)
        self.assertIn('guard let context, let configurationRevision else { invalidate(); return }',source)
        for forbidden in ['await ', 'URLSession', 'WorkshopOwnedReadApproval(', '.load(', 'UserDefaults']:
            self.assertNotIn(forbidden,source)
    def test_authored_identity_close_configuration_regressions(self):
        source=(ROOT/'Tests/AppUnitTests/WorkshopOwnedSessionBindingTests.swift').read_text()
        for expected in ['testNilContextOrConfigurationNeverConstructs','testRepeatedReconciliationRetainsSameBrowserWithoutFetching','testCloseListRetainsBindingForSafeReopen','testEveryAuthorityReplacementInvalidatesBeforeFactory','testConfigurationReplacementAndRemovalInvalidate','testExplicitInvalidationFencesIntermediateABA','testMissingFactoryResultRemainsClosedUntilExplicitConfigurationChange']:
            self.assertIn(expected,source)
if __name__=='__main__': unittest.main()

import pathlib, unittest, json
ROOT=pathlib.Path(__file__).resolve().parents[2]
class LicenseRemovalContracts(unittest.TestCase):
    def setUp(self):
        self.model=(ROOT/'App/MerchantOnboardingModel.swift').read_text()
        self.view=(ROOT/'App/MerchantOnboardingView.swift').read_text()
        a=self.model.index('    struct LicenseRemoval:'); b=self.model.index('    func uploadSelected()',a)
        self.addition=self.model[a:b]
    def test_local_only_and_exact_field(self):
        self.assertIn('draft.license = nil; errorKey = draft.blocker(step: 3); revision += 1',self.addition)
        for forbidden in ['Task {','await ','URLRequest','uploadLicense(','submit(','draft = .init()']:
            self.assertNotIn(forbidden,self.addition)
    def test_current_identity_draft_revision_and_one_shot(self):
        for x in ['request.identity == identity','request.generation == generation','request.revision == revision','request.draft == draft','pendingLicenseRemovalID == request.id','pendingLicenseRemovalID = nil']:
            self.assertIn(x,self.addition)
    def test_state_and_auth_fences(self):
        for x in ['!isBusy','!coordinator.isUploading','identity == coordinator.identity','coordinator.identityGate == .registered','!coordinator.submission.isLocked','confirmation == nil','selectedImage == nil','selectedBrandImage == nil','case .loaded(.none)','application.canReapply']:
            self.assertIn(x,self.addition)
    def test_normal_entry_and_confirmation(self):
        self.assertIn('merchant.onboarding.license.remove',self.view)
        self.assertIn('presenting: licenseRemoval',self.view)
        self.assertIn('model.cancelLicenseRemoval(request)',self.view)
        self.assertIn('model.removeLicense(request)',self.view)
        self.assertIn('phase != .active',self.view)
    def test_existing_replacement_and_registration_paths_present(self):
        self.assertIn('Task { await model.uploadSelected() }',self.view)
        self.assertIn('model.prepare(); showSubmitConfirmation = model.confirmation != nil',self.view)
        self.assertIn('model.submitConfirmed()',self.view)
    def test_bilingual_and_native_cases(self):
        fragment=json.loads((ROOT/'Resources/MerchantOnboardingLicenseRemovalLocalizations.fragment.json').read_text())
        for v in fragment.values(): self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
        tests=(ROOT/'Tests/AppUnitTests/MerchantOnboardingLicenseRemovalTests.swift').read_text()
        self.assertEqual(tests.count('    func test'),10)
if __name__=='__main__':unittest.main()

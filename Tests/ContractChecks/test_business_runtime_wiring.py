"""Supplementary source guards, not Swift compiler or live service verification."""
import json, pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class BusinessRuntimeWiringTests(unittest.TestCase):
    def read(self,p): return (ROOT/p).read_text()
    def test_independent_default_off_configuration_and_bounded_transport(self):
        app=self.read('App/AppSession.swift');deps=self.read('App/NativeRuntimeDependencies.swift');core=self.read('Core/BusinessRuntimeConfiguration.swift')
        for text in ['businessConfiguration: BusinessRuntimeConfiguration? = nil','bankDocument: (any BankWithdrawalCurrentDocumentProviding)? = nil']:self.assertIn(text,deps)
        self.assertIn('configuration.matches(context)',app)
        self.assertIn('ResponseLimitedHTTPTransport(enabled: configuration.matches(context))',app)
        for text in ['routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]','bankChallengeActions: Set<BankWithdrawalServerAction> = []','imImageSelection: Bool = false','stampCamera: Bool = false','verificationCamera: Bool = false']:self.assertIn(text,core)
        self.assertNotIn('URLSession',core)
    def test_exact_method_feature_path_and_session_binding(self):
        core=self.read('Core/BusinessRuntimeConfiguration.swift')
        for text in ['feature.accepts($0)','market == .china','context.market == market','baseURL == context.baseURL','namespace == context.session.namespace','accountID == context.session.accountID','current() == captured','captured.session.token','$0.method == request.httpMethod','appendingPathComponent($0.path) == parts.url']:self.assertIn(text,core)
        self.assertEqual(core.count('transport.send(request)'),1);self.assertIn('features == [.bankPrepare, .bankCreate]',core);self.assertIn('bankActions.contains(.confirm)',core)
    def test_bank_normal_entry_mounts_without_fabricating_document_or_consent(self):
        self.assertIn('bankWithdrawalDestination',self.read('App/QuestifyApp.swift'))
        self.assertIn('if let bankDestination { bankDestination() }',self.read('App/WithdrawalSupportLandingView.swift'))
        app=self.read('App/AppSession.swift')
        for text in ['let provider = runtimeDependencies.bankDocument','BankWithdrawalConsentReader(', 'refreshConsent: { try await consent.refresh() }','validatedChallenge: { routes.validatedChallenge($0) }']:self.assertIn(text,app)
        core=self.read('Core/BankWithdrawalConsentReader.swift')
        for text in ['provider.currentDocument(context: captured)','api/compliance/consents/latest','result.valid','document = nil; evidence = nil']:self.assertIn(text,core)
        self.assertNotIn('api/agreement/get',core)
        self.assertNotIn('"eventType":"AGREE"',core)
    def test_bank_refreshes_before_prepare_and_confirm_and_preserves_pending_lock(self):
        s=self.read('Core/BankWithdrawalAdapter.swift')
        self.assertEqual(s.count('try await refreshConsent?()'),2)
        prepare=s.split('public func prepare(')[1].split('private func requireProof')[0]
        self.assertLess(prepare.index('try await refreshConsent?()'),prepare.index('try authorizedRequest'))
        submit=s.split('public func submit(')[1].split('public func reject(')[0]
        self.assertLess(submit.index('try await refreshConsent?()'),submit.index('let confirm'))
        self.assertIn('validatedChallenge(value.challengeID)',prepare)
        self.assertNotIn('func reset',s)
    def test_stamp_upload_create_origins_and_camera_are_separate(self):
        s=self.read('App/AppSession.swift').split('func makeRoamStampCaptureCoordinator')[1].split('func makeRoamPosterCoordinator')[0]
        for text in ['factory.client([.stampUpload])','factory.permits(.stampUpload)','factory.client([.stampCreate])','factory.approval([.stampCreate])','approvedImageOrigins: factory.configuration.stampImageOrigins','StoredRoamStampPending']:self.assertIn(text,s)
        self.assertIn('cameraEnabled: session.stampCameraEnabled',self.read('App/SessionRoamMediaViews.swift'))
    def test_im_default_disabled_but_configured_writer_reaches_real_client(self):
        s=self.read('App/AppSession.swift')
        for text in ['disabledIMWriter = IMExpandedWriter(service: nil','IMExpandedService(configuration: configuration, transport: factory.client(features)','enabledPaths: Set(factory.routes(features).map(\\.path))','self.currentRuntimeDependencyContext == captured','factory.configuration.imImageSelection']:self.assertIn(text,s)
        self.assertIn('selectionApproval?() ?? self.nativeSelectionEnabled',self.read('App/RetainedImagePresenterHost.swift'))
        self.assertNotIn('nativeSelectionEnabled = true',s)
    def test_publish_reads_writes_owner_and_unknown_storage_remain_distinct(self):
        s=self.read('App/AppSession.swift')
        for text in ['factory.permits(.publishingRead)','factory.approval([.publishingWrite])','factory.permits(.projectRead)','factory.approval([.projectWrite])','owner: owner','store: projectDraftStore','else { service = ProjectEditDisabledService() }']:self.assertIn(text,s)
        self.assertIn('owner: seed.owner',self.read('App/SessionPublishingModesView.swift'))
        self.assertIn('OperationDefaultsJournal(defaults: .standard)',s)
    def test_production_verification_is_not_labeled_synthetic(self):
        s=self.read('Core/MerchantBusinessService.swift')
        self.assertIn('canExecuteSyntheticMutation: Bool { mutationTransport != nil }',s)
        self.assertIn('canExecuteVerificationMutation: Bool { mutationTransport != nil || verificationTransport != nil }',s)
        self.assertIn('guard let mutationTransport else',s)
        boundary=self.read('Core/MerchantVerificationHTTPTransport.swift')
        for text in ['request.httpMethod == "POST"','Self.paths.contains','transport.permits(request)']:self.assertIn(text,boundary)
        self.assertIn('reader.canExecuteVerificationMutation',self.read('Core/NativeVerificationWorkflow.swift'))
        self.assertNotIn('testingMutationTransport:',self.read('App/AppSession.swift'))
    def test_authored_fake_tests_and_new_copy_exist(self):
        self.assertEqual(self.read('Tests/CoreTests/BusinessRuntimeTests.swift').count('func test'),11)
        self.assertEqual(self.read('Tests/CoreTests/BankWithdrawalConsentReaderTests.swift').count('func test'),7)
        s=self.read('Tests/CoreTests/BankWithdrawalTests.swift')
        self.assertIn('testConsentIsRefreshedAgainBeforeConfirmation',s)
        self.assertIn('testRefreshFailureBeforePreflightCannotSendOrReserveMoneyOperation',s)
        f=json.loads(self.read('Resources/BusinessRuntimeLocalizations.fragment.json'))['strings'];c=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for k,v in f.items():self.assertEqual(v,c[k]);self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()

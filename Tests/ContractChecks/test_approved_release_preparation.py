"""Offline source checks, not Swift execution or proof of server approval."""
import json
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ApprovedReleasePreparationContracts(unittest.TestCase):
    def read(self,path):return (ROOT/path).read_text()
    def test_ordinary_host_and_exact_default_empty_capability(self):
        session=self.read('App/AppSession.swift')
        self.assertIn('makeApprovedReleasePreparationSource(owner:',session)
        self.assertIn('factory.permits(.approvedTopicReleasePrepare)',session)
        self.assertIn('currentRuntimeDependencyContext == captured',session)
        config=self.read('Core/BusinessRuntimeConfiguration.swift')
        self.assertIn('case .approvedTopicReleasePrepare:',config)
        self.assertIn('ApprovedTopicReleasePaths.prepare',config)
        core=self.read('Core/ProjectEditCoordinator.swift')
        self.assertIn('releasePreparationSource: (any ApprovedTopicReleasePreparing)? = nil',core)
        host=self.read('App/ProjectEditView.swift')
        self.assertIn('ApprovedReleaseAuthorReadSection(model: model, controller: approvedRelease)',host)
        self.assertIn('approvedRelease.binding(releasePresentation)',host)
    def test_capture_and_dismissal_never_reacquire_new_presentation(self):
        s=self.read('App/ApprovedReleaseAuthorPresentation.swift')
        for token in ['model.editorIncarnation == opening.incarnation','model.ownsVisit','ProjectEditLocalStore.exactPending(pending, opening.pending)','ObjectIdentifier(source) == ObjectIdentifier(opening.source)','presentation?.id == original.id','self.close(original)','controller.open(opening)']:
            self.assertIn(token,s)
        ui=self.read('App/ApprovedReleasePreparationView.swift')
        self.assertIn('.task(id: original.id)',ui);self.assertIn('.onDisappear { original.publisher?.close(); original.flow.close() }',ui)
        for token in ['AsyncImage','URLSession','model.draft','coordinator.pending']:self.assertNotIn(token,ui)
    def test_actual_client_owns_read_and_checks_identity_before_401(self):
        s=self.read('Core/ApprovedTopicReleasePreparationClient.swift')
        for token in ['ownedTask = task','guard state != .loading','withTaskCancellationHandler','ownedTask?.cancel()','requestID == request','currentCredentials() == credentials','ProjectEditOwner.personal.rawValue','ProjectEditProduct.city.rawValue']:
            self.assertIn(token,s)
        self.assertLess(s.index('try check(credentials)',s.index('await transport.send')),s.index('if status == 401'))
        self.assertNotIn('onUnauthorized',s)
    def test_strict_capture_decoder_has_resource_and_field_boundaries(self):
        s=self.read('Core/ApprovedTopicReleaseDomain.swift')
        for token in ['depth <= 32','tokens <= 100_000','data.count <= 4 * 1024 * 1024','ContentDraftJSON.parse','releaseAllocated"] == .bool(false)','secretValuesExcluded"] == .bool(true)','nodeIDs.insert(id).inserted','guard image == nil || image == ""']:
            self.assertIn(token,s)
        self.assertLess(s.index('for byte in data'),s.index('ContentDraftJSON.parse'))
    def test_synthetic_wire_is_debug_only_and_tests_use_real_buttons(self):
        s=self.read('Core/ApprovedTopicReleaseSyntheticFixtures.swift');self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('ApprovedTopicReleasePreparationClient',s);self.assertIn('func send(_ request: URLRequest)',s)
        ui=self.read('Tests/AppUITests/ApprovedReleasePreparationFlowTests.swift')
        for token in ['tap("approvedRelease.read"','tap("approvedRelease.retry"','"73"','"41"','Array(target.label.utf8)','assertFixtureEnvironment','projectEdit.fixture.signOut']:
            self.assertIn(token,ui)
        self.assertEqual(ui.count('func test'),2);self.assertEqual(ui.count('UNMEASURED complete method estimate: 720 seconds.'),2)
        self.assertEqual(self.read('Tests/CoreTests/ApprovedTopicReleasePreparationTests.swift').count('func test'),15)
        self.assertEqual(self.read('Tests/AppUnitTests/ApprovedReleaseAuthorPresentationTests.swift').count('func test'),4)
    def test_additive_catalog_is_bilingual(self):
        fragment=json.loads(self.read('Resources/ApprovedReleaseLocalizations.fragment.json'))
        self.assertGreaterEqual(len(fragment['strings']),30)
        for key,value in fragment['strings'].items():
            self.assertTrue(key.startswith('approvedRelease.'))
            self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
            self.assertTrue(value['localizations']['zh-Hans']['stringUnit']['value'])


    def test_actual_category_fields_are_distinct_read_metadata_and_persisted_exactly(self):
        domain = self.read('Core/ApprovedTopicReleaseDomain.swift')
        self.assertIn('templateCategoryID: Int?', domain)
        self.assertIn('optionalNonnegativeInteger(source, "templateCategoryId")', domain)
        self.assertIn('templateCategoryIDs: optionalText(source, "templateCategoryIds")', domain)
        storage = self.read('Core/ApprovedTopicReleasePublication.swift')
        self.assertIn('"templateCategoryId": n.templateCategoryID.map', storage)
        fields = storage.split('public var fields:')[1].split('static func decode')[0]
        self.assertNotIn('templateCategoryId', fields)
        self.assertIn('testMissingLegacyCategoryAndExplicitNullStayAbsentWhileMistypedValuesReject', self.read('Tests/CoreTests/ApprovedTopicReleasePreparationTests.swift'))
        self.assertIn('approvedRelease.confirm.chapter.0.block.1.templateCategory', self.read('Tests/AppUITests/ApprovedReleasePublicationFlowTests.swift'))

    def test_current_empty_401_precedes_body_parse_but_never_identity_validation(self):
        source=self.read('Core/ApprovedTopicReleasePreparationClient.swift')
        response=source.split('let (data, status) = try await transport.send(request)')[1].split('return try ApprovedTopicReleasePreparation.decode')[0]
        self.assertLess(response.index('try check(credentials)'),response.index('if status == 401'))
        self.assertLess(response.index('if status == 401'),response.index('ApprovedTopicReleaseWire.envelope(data)'))
        tests=self.read('Tests/CoreTests/ApprovedTopicReleasePreparationTests.swift')
        self.assertIn('testCurrentEmptyOrMalformedBody401UsesUnauthorizedFlowState',tests)
        self.assertIn('testOldSessionEmptyBody401IsRejectedBeforeHTTPAuthenticationClassification',tests)
if __name__=='__main__':unittest.main()

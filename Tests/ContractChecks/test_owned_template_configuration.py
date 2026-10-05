"""Owner-inspector source checks supplement, not replace, Apple execution."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(p):return (ROOT/p).read_text()
class OwnedTemplateConfiguration(unittest.TestCase):
    def test_separate_nonserializable_owner_snapshot_before_secret_projection(self):
        s=read('Core/OwnedTemplateConfiguration.swift')
        self.assertIn('public struct OwnedTemplateConfigurationSnapshot {',s)
        self.assertIn('private let originalResponse: Data',s)
        self.assertIn('fields["id"]?.integer == requestedID.rawValue',s)
        self.assertIn('fields["memberId"]?.integer == accountID',s)
        self.assertLess(s.index('fields["memberId"]?.integer == accountID'),s.index('qa = Dictionary'))
        self.assertNotIn('Codable {',s)
        self.assertIn('case .string(let text)',s)
        public=read('Core/MemberTemplateDetail.swift')
        self.assertNotIn('questionAnswer:',public);self.assertNotIn('advancedConfigJson:',public)
    def test_unknown_missing_and_unsupported_method_preservation(self):
        s=read('Core/OwnedTemplateConfiguration.swift')
        for value in ['case missing, null, value(String), unsupported','[1, 3].contains(validationMethod)','originalResponse = response','known.contains($0)','qa.filter { $0.value == .unsupported }','rows.allSatisfy({ $0.object != nil })']:
            self.assertIn(value,s)
        self.assertNotIn('TemplateAdvancedDraft(raw:',s);self.assertNotIn('?? .manual',s)
        self.assertNotIn('saveLocal(',s);self.assertNotIn('TemplateAuthoringContract.request',s)
    def test_normal_factory_keeps_existing_read_fence_and_no_writer(self):
        s=read('Core/TemplateShelfReadApproval.swift').split('func ownedConfiguration')[1].split('public func detail')[0]
        self.assertIn('"api/template/myinfo"',s);self.assertIn('fields: ["id": String(id.rawValue)]',s)
        self.assertIn('try await send(request, acceptsResult: acceptsResult)',s);self.assertNotIn('api/template/info',s)
        factory=read('App/AppSession.swift').split('func makeOwnedTemplateConfigurationHost')[1].split('private var retainedOwnedMemberReader')[0]
        self.assertIn('makeTemplateShelfReadTransport()',factory);self.assertNotIn('TemplateAuthoringHTTPTransport',factory)
    def test_existing_professional_components_reused_readonly(self):
        view=read('App/OwnedTemplateConfigurationView.swift')
        for value in ['TemplateAuthoringQAFields','TemplateStoryBeatFields','readOnly: true','session.templateShelfViewIdentity','OwnedTemplateStoryConfigurationView(host: host, expectedID: id)','host.snapshot','host.clear()','.privacySensitive()']:
            self.assertIn(value,view)
        for forbidden in ['adopt(', 'open(seed:', 'saveLocal(', 'prepare(.', 'submit(', 'TemplateAuthoringCoordinator(']: self.assertNotIn(forbidden,view)
        original=read('App/TemplateAuthoringDetailForms.swift')
        self.assertIn('TemplateAuthoringQAFields(method: model.draft.validationMethod',original)
        self.assertIn('model.optional($0.draftPath)',original)
    def test_authored_regressions_and_scope_clear_present(self):
        core=read('Tests/CoreTests/OwnedTemplateConfigurationTests.swift')
        for name in ['testFreshOwnerOnlyProjectionKeepsExactBaselineAndDistinctProvenance','testWrongMissingOwnerIDAndNoncanonicalOwnerCannotConstructSnapshot','testMissingNullEmptyAndUnsupportedValuesNeverBecomeEditorDefaults','testUnsupportedMethodsAndAdvancedDataAreNotRewrittenOrApplied','testStoryReadKeepsWhitespaceLegacyImagesUnknownFieldsAndRejectsCorruption','testHostRevocationClearsOwnerSnapshotWithoutGivingAnyWriteCapability']:
            self.assertIn(name,core)
        app=read('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift')
        self.assertIn('for target in ["shelf", "detail", "ownerConfiguration"]',app)
        self.assertIn('testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange',app)
        self.assertIn('let ownerHost = session.makeOwnedTemplateConfigurationHost(); await ownerHost.load(id: id)',app)
        ui=read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift')
        self.assertIn('testNormalRootOwnedConfigurationReadOnlyAndStoryReturn',ui)
        self.assertIn('.task(id: id)', read('App/OwnedTemplateConfigurationView.swift'))
        self.assertIn('snapshot.id == expectedID', read('App/OwnedTemplateConfigurationView.swift'))
        self.assertIn('testNewSelectionWinsWhilePriorTemplateSuccess401OrErrorIsPending', core)
        self.assertEqual(read('Core/TemplateShelfReadApproval.swift').count('acceptsResult()'), 3)

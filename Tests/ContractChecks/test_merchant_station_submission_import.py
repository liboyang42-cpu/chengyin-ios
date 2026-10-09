"""Scoped source contracts; these do not compile or execute Swift/XCTest."""
from pathlib import Path
import hashlib,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
OLD_EDITOR_HUNK = b'            Section { field("submissionId"); Toggle("merchant.content.approve", isOn: Binding(get: { approve }, set: { approve = $0; dirty = true; model.cancel() }))\n                if !approve { reasonPicker(["ANSWER_MISMATCH", "EVIDENCE_UNCLEAR", "DUPLICATE_SUBMISSION"]) }\n'
NEW_EDITOR_HUNK = b'            MerchantStationSubmissionImportView(owner: model, snapshot: snapshot, nodeID: station["nodeId"].safeInteger ?? 0, text: $text, approve: $approve) {\n                dirty = true; model.cancel()\n'
EDITOR_BASE_SHA = '4caceb48edf13be3860d51faeedd9e5c89615642d7d2c1273cc1388d47dff109'
PROTECTED = {'Core/MerchantStationContracts.swift': '54d04df6f2f28571617f084c3c6cd7fcf1b6601b0c0fa587af88314dcad48c61', 'Core/MerchantStationServiceWindow.swift': '62e93707db9f0bbad6e1f28477e012524b299930edfc6e03493c1a1c1d57066b', 'Core/MerchantContentCommands.swift': 'bd0b132835c2e2fdc19ed7dcacc87de08d435cff8e828599b40a11eb261940c5', 'Core/MerchantContentCoordinator.swift': '9648d423ec3e1648ef6b764a7ca708b91f9c005f096fd2c683760c3267ee9b84', 'Core/MerchantContentDomain.swift': '3b0c38a01132ed9bfbb164b0b2b5e81113df6869e0afa48376df3afded7ae19f', 'Core/MerchantContentService.swift': 'cf85b10be41628a483a5954d37b49a03a3f88c5946fe2987e224d9c0f07e1434', 'Core/MerchantContentSyntheticFixtures.swift': 'c491bde66076668ca9f8b5ffd0efb79aada5b5d314c9f9dd021998c8dd055d30', 'App/MerchantContentViews.swift': '334b0060952d2a927feb9e2185a413145e991f97a60e2987fafd2f60235c22a5', 'App/MerchantStationServiceTimeFields.swift': 'cba6d695d61a9ad41b616672d6822bfdc9fdfdab9bc0fd4d42afd4a0a7e78f6e', 'App/MerchantStationLiveCodeView.swift': '992eeff1dbeab2726a3539f988216a67b1e8f23d57884e402403f6eb24873c19', 'App/NativeQRScanner.swift': '68d9142971fbcd77a919ca6e2df48e37c77314531bbbe5df8654deec6a8de98b', 'App/NativeVerificationView.swift': '59dfee22ba0d324cd57777695b4e6d94209c80e43824245228b2280839faf66f', 'Core/BusinessRuntimeConfiguration.swift': '6c6b0948f358b64fe039c9dbdcefed01ed33d7f97207444185dfdc227be7ba7b', 'App/MerchantBusinessEditor.swift': '7a4720def304cac5beebc94221fdb55995a00b28a80d56e20d0e7ef964f86424', 'App/MerchantAftercareEvidenceFlow.swift': '55d5c3e7c8cb41b0a436786dd0c0eda441999c8b575e4c34a73dfa9c721ba7ce', 'App/MerchantEngagementViews.swift': '7664daffbe1e9846bac66b8de675761fffd2cd0e93b2e792699ae04cae5c1128', 'App/MerchantOperationsViews.swift': '62c9d5c038026c4dd8cc7a5c1389aff5caf4308bad0f2df33eeb23b084271833'}

class SubmissionImportContracts(unittest.TestCase):
    def setUp(self):
        self.parser=(ROOT/'Core/MerchantStationSubmissionCode.swift').read_text()
        self.view=(ROOT/'App/MerchantStationSubmissionImportView.swift').read_text()
        self.editor=(ROOT/'App/MerchantContentEditor.swift').read_text()
    def test_exact_single_editor_inverse_preserves_every_other_hunk(self):
        raw=(ROOT/'App/MerchantContentEditor.swift').read_bytes()
        self.assertEqual(raw.count(NEW_EDITOR_HUNK),1)
        self.assertEqual(hashlib.sha256(raw.replace(NEW_EDITOR_HUNK,OLD_EDITOR_HUNK)).hexdigest(),EDITOR_BASE_SHA)
    def test_existing_services_commands_journal_and_scanners_unchanged(self):
        for path,expected in PROTECTED.items():self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),expected,path)
    def test_parser_bounds_before_trimming_and_never_coerces_via_float(self):
        self.assertIn('maximumInputBytes = 4_096',self.parser)
        self.assertLess(self.parser.index('raw.utf8.count <='),self.parser.index('raw.trimmingCharacters'))
        self.assertIn('let identifier = Int64(candidate), identifier > 0',self.parser)
        for token in ['JSONSerialization','Double(', 'URLComponents(', 'URLSession', 'openURL']:self.assertNotIn(token,self.parser)
    def test_json_single_field_and_query_single_identifier_are_strict(self):
        self.assertIn('"submissionId"[ \\t\\r\\n]*:',self.parser)
        self.assertIn('(?:"([1-9][0-9]{0,18})"|([1-9][0-9]{0,18}))',self.parser)
        self.assertIn('\\}\\z',self.parser)
        self.assertIn('value.hasPrefix("?submissionId=")',self.parser)
        self.assertIn('candidate.utf8.allSatisfy({ (48...57).contains($0) })',self.parser)
    def test_all_absolute_links_fail_closed_without_host_inference(self):
        self.assertIn('!value.contains("://"), !value.hasPrefix("//")',self.parser)
        self.assertIn('throw Failure.unsupportedLink',self.parser)
    def test_no_new_device_network_persistence_or_clipboard_action(self):
        for token in ['UIPasteboard','PasteButton','NativeQRScanner','AVCapture','requestAccess','URLSession','openURL','UserDefaults','FileManager','service.load(','service.perform(','owner.prepare(','model.prepare(']:
            self.assertNotIn(token,self.view+self.parser)
    def test_input_preview_apply_are_three_separate_steps(self):
        for token in ['func update(', 'func preview()', 'func apply() -> Bool', 'session.update', 'session.preview()', 'session.apply()'] :self.assertIn(token,self.view)
        self.assertIn('code = try .init(raw); raw = ""',self.view)
        self.assertIn('SecureField("merchant.submissionImport.input"',self.view)
        self.assertIn('Section("merchant.submissionImport.unverified")',self.view)
    def test_context_is_exact_current_observation_and_authorized_station(self):
        for token in ['snapshot.access.active','projection.allows(.verify, nodeID: nodeID)','snapshot.query == .game(activityID: projection.activityID)','lhs.snapshot.observedAt == rhs.snapshot.observedAt','lhs.bytes == rhs.bytes','owner.isCurrent','owner.service.isConfigured','!owner.busy, !owner.locked','owner.review == nil, owner.receipt == nil','current.scope == owner.service.scope']:
            self.assertIn(token,self.view)
    def test_raw_draft_uses_utf8_and_all_fields_not_only_identifier(self):
        for token in ['lhs.approve == rhs.approve','lhs.text.count == rhs.text.count','lhs.text.allSatisfy','value.utf8.elementsEqual(other.utf8)','currentDraft() == original','draft == original']:self.assertIn(token,self.view)
    def test_manual_edit_and_lifecycle_generation_prevent_aba(self):
        for token in ['generation == permit','self.generation == captured','model.invalidate(); approve = $0','model.invalidate(); text[name] = $0','.onChange(of: scenePhase)','.onDisappear { model.deactivate() }','.onChange(of: context)','.onChange(of: draft)']:
            self.assertIn(token,self.view)
        self.assertIn('let permit = model.generation',self.view)
    def test_final_stage_is_synchronous_and_preserves_decision_and_reason(self):
        apply=self.view[self.view.index('@discardableResult func apply()'):self.view.index('    func retire(')]
        self.assertNotIn('await ', '\n'.join(line.split('//')[0] for line in apply.splitlines()))
        self.assertLess(apply.index('guard isCurrent'),apply.index('stage(code.submissionID)'))
        callback=self.view[self.view.index('currentDraft: { draft }'):self.view.index('            }.disabled')]
        self.assertIn('text["submissionId"] = identifier; didChange(); return true',callback)
        self.assertNotIn('approve =',callback);self.assertNotIn('reasonCode',callback)
        self.assertIn('utf8.elementsEqual(identifier.utf8) { return true }',callback)
    def test_cancel_retirement_scrubs_memory_and_old_cancel_cannot_close_new_sheet(self):
        self.assertIn('guard session?.id == id else { return }; invalidate()',self.view)
        self.assertIn('session?.retire(); session = nil',self.view)
        self.assertIn('retired = true; raw = ""; code = nil',self.view)
    def test_actual_sheet_binding_captures_presented_id_for_get_and_dismiss(self):
        binding=self.view[self.view.index('    func presentationBinding()'):self.view.index('    func open(')]
        self.assertIn('let presentedID = session?.id',binding)
        self.assertIn('self.session?.id == presentedID',binding)
        self.assertIn('guard value == nil, let presentedID else { return }',binding)
        self.assertIn('self?.cancel(id: presentedID)',binding)
        self.assertIn('.sheet(item: model.presentationBinding())',self.view)
        self.assertNotIn('let id = model.session?.id { model.cancel',self.view)
        tests=(ROOT/'Tests/AppUnitTests/MerchantStationSubmissionImportTests.swift').read_text()
        self.assertIn('testOldPresentationBindingCannotDismissOrExposeReopenedSession',tests)
        self.assertIn('oldBinding.wrappedValue = nil',tests)
    def test_manual_controls_retain_existing_labels_ids_and_reason_choices(self):
        for token in ['merchant.content.field.submissionId','merchant.content.approve','merchant.content.field.reasonCode','merchant.content.chooseReason','ANSWER_MISMATCH','EVIDENCE_UNCLEAR','DUPLICATE_SUBMISSION','.textInputAutocapitalization(.sentences).autocorrectionDisabled()']:
            self.assertIn(token,self.view)
        self.assertIn('dirty = true; model.cancel()',self.editor)
    def test_localizations_cover_labels_and_truthful_scope(self):
        fragment=json.loads((ROOT/'Resources/MerchantStationSubmissionImportLocalizations.fragment.json').read_text())
        keys=set(re.findall(r'merchant\.submissionImport\.[A-Za-z]+',self.view))-{'merchant.submissionImport.cancel'}
        self.assertEqual(set(fragment),keys);self.assertEqual(len(fragment),15)
        for value in fragment.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
        self.assertIn('not been checked',fragment['merchant.submissionImport.unverifiedBody']['localizations']['en']['stringUnit']['value'])
        self.assertIn('does not support camera',fragment['merchant.submissionImport.noCamera']['localizations']['en']['stringUnit']['value'])
    def test_negative_lifecycle_and_preservation_xctests_are_authored(self):
        core=(ROOT/'Tests/CoreTests/MerchantStationSubmissionCodeTests.swift').read_text();app=(ROOT/'Tests/AppUnitTests/MerchantStationSubmissionImportTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',core)),19);self.assertEqual(len(re.findall(r'func test',app)),23)
        for token in ['testDuplicateJSONIDs','testMultipleQueryIDs','testOversizedInput','testAbsoluteAndNetworkPathLinks','testExactIntegerBeyondJavaScriptPrecision']:self.assertIn(token,core)
        for token in ['testCancelPreservesBytes','testManualEditABA','testBackgroundAndReturn','testRawDraftUnicodeOnlyChange','testChangedScopeAuthenticationOrConfiguration','testExistingDecisionReviewBlocksImport','testExplicitApplyChangesOnlyID']:self.assertIn(token,app)

if __name__=='__main__':unittest.main(verbosity=2)

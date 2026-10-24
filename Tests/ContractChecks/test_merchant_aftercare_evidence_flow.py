"""Focused source-only evidence-flow contracts; hosted Swift/Apple execution is separate."""
from pathlib import Path
import hashlib
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
INVERSES = {'App/MerchantBusinessEditor.swift': {'base_sha256': '87140c2bb2fe9af384af57908fa98e1186fc75dcaf273ecc66d8f78ec40fc671', 'hunks': [(536, b'@Environment(\\.merchantAftercareEvidenceDependencies) private var evidenceDependencies\n    ', b''), (713, b'\n    var aftercareEvidenceOwner: (() -> MerchantAftercareEvidenceOwner?)? = nil', b''), (1322, b'?\n    @State private var evidenceFlow: MerchantAftercareEvidenceFlow', b''), (4192, b'Button("merchant.aftercareEvidence.open") { openAftercareEvidence(row) }\n                        .disabled(evidenceDependencies == nil || pendingAftercareDecision != nil)\n                        .accessibilityIdentifier("merchant.aftercareEvidence.open")\n                    ', b''), (5786, b'\n                    retireEvidenceFlow()', b''), (7999, b'sheet(item: $evidenceFlow, onDismiss: { retireEvidenceFlow() }) { flow in\n                MerchantAftercareEvidenceSheet(model: flow)\n            }\n            .onChange(of: context.id) { _, _ in retireEvidenceFlow() }\n            .onChange(of: snapshot) { _, _ in retireEvidenceFlow() }\n            .onChange(of: aftercareEvidenceDraft) { _, _ in retireEvidenceFlow() }\n            .onChange(of: confirmAftercareDecision) { _, showing in if showing { retireEvidenceFlow() } }\n            .', b''), (8949, b' }\n    private var aftercareEvidenceDraft: MerchantAftercareEvidenceDraft {\n        .init(decision: decision, content: content, evidence: evidence)\n    }\n    private func openAftercareEvidence(_ row: MerchantBusinessRecord) {\n        guard evidenceFlow == nil, pendingAftercareDecision == nil, let evidenceDependencies,\n              let owner = aftercareEvidenceOwner?(), owner.editorID == context.id, owner.snapshot == snapshot,\n              owner.snapshot.document.rows.contains(row) else { return }\n        let original = aftercareEvidenceDraft\n        evidenceFlow = MerchantAftercareEvidenceFlow(owner: owner, dependencies: evidenceDependencies, original: original,\n            currentDraft: {\n                guard context.id == owner.editorID, snapshot == owner.snapshot, pendingAftercareDecision == nil,\n                      case .aftercare(let current) = context.kind, current == row else { return nil }\n                return aftercareEvidenceDraft\n            }, applyKey: { key in evidence = key; issue = nil })\n    }\n    private func retireEvidenceFlow() { evidenceFlow?.retire(); evidenceFlow = nil', b'')]}, 'App/MerchantBusinessViews.swift': {'base_sha256': 'c4fa6f3121f7a7d69c21e27b384b2c1999fa080abacb19a6fcbdc23daa74169a', 'hunks': [(23142, b'aftercareEvidenceOwner: {\n                MerchantAftercareEvidenceOwner(editorID: context.id, document: model,\n                    editorIsCurrent: { editor?.id == context.id && pendingMutation == nil })\n            }, ', b'')]}, 'App/MerchantHomeView.swift': {'base_sha256': 'f03b2f272e087c91e5d2f3383049e4bc2524ccddacb60f597f605dfb027756a8', 'hunks': [(6440, b'\n                       ', b''), (6539, b'\n                            .environment(\\.merchantAftercareEvidenceDependencies, aftercareEvidenceDependencies(journal: businessJournal))\n                            ', b''), (6732, b'\n                   ', b''), (12176, b'aftercareEvidenceDependencies(journal: any MerchantBusinessIntentStore) -> MerchantAftercareEvidenceDependencies? {\n        guard let engagementReader, let exportRecovery else { return nil }\n        return .init(reader: engagementReader, journal: journal, recovery: exportRecovery)\n    }\n    private func ', b'')]}}
PROTECTED = {'Core/MerchantEngagementCoordinator.swift': '87b0115825e029455656f15ee18cc0f2b1505c8c86ef806264a0b496c1b1479c', 'Core/MerchantEngagementReading.swift': '2a8b8d87151080f337445383018e4e299058a894ae8a91295050bf13330e1225', 'Core/MerchantEngagementService.swift': '559b44acd7453f11a474763c22d6e110c1575332f315dfb5463472c216780893', 'Core/MerchantEngagementProduction.swift': 'a58f4f0c8ee3282426968a74d68f7748aa6f4e04fd2acfe86fe52571b88c4073', 'Core/MerchantAftercareEvidenceAdapter.swift': '59b48e64d0f5965fea6af16d4e334d2ad611bad79e94c21d2ba3ef8aa06f865f', 'Core/MerchantEvidenceSelection.swift': '197475da1ef678e2a8ace791ddca0e2b6bc76bca0d74872f3c6848c8e8d760de', 'Core/MerchantBusinessCoordinator.swift': '2d02730db4af7d1e3edc571e5aa4a991e50cd4edbf40eb7478cdb42195fd5711', 'Core/MerchantBusinessMutation.swift': '4695496ea387604f10c7749f270780472f8a9a39fc20fd712def1b12a7a37b0b', 'Core/MerchantBusinessReading.swift': '906e62610186c515532f1e19898f9ae56bb97652216064415d152978ca4e1c93', 'Core/MerchantBusinessService.swift': '632a5653e3186a41d954c4fd4e01a3928d6c797ad64f08b36624fa8dd97ae5c2', 'Core/MerchantBusinessQuery.swift': '8ae347444e61e6d14ad9b981701a0d73f5c6bdad9c52c31a22220a720d25de49', 'Core/MerchantRedemptionFilter.swift': 'd0a349ba6e3833d1ed72d914dd9a8605568940e9135153f63192637c0cfe0294', 'App/MerchantEvidenceSelectionView.swift': '514a00adefb6d7774dbb1ee1ad4ced6371835ac805ac2cce710cbfda684c5eb8', 'App/MerchantEngagementViews.swift': '7664daffbe1e9846bac66b8de675761fffd2cd0e93b2e792699ae04cae5c1128', 'App/MerchantEngagementComposer.swift': '59006e3daee72a2c99d12d5cdfd6035b85a51e9a8033788bdf25c15e47ce0b11', 'App/MerchantEngagementViewModel.swift': '1d5e6bc954d710c15f655bcfb884aa1b8d24a2c19b611d428a3d0b3ae7bae746', 'App/AppSession.swift': 'd6a39320f8978fc5179ce615bf9335a510dd2f3280901e093f2d0187bbb65187', 'Resources/Localizable.xcstrings': 'e35252e25132fbefbe2ffc9aa15b5fb1e8a79dc8d3dbf3470b979bc644b98933', 'Questify.xcodeproj/project.pbxproj': '297b314d8d6f3283bfc637623d7afdcd3977f6305348f727cca029c544f41c35', 'tools/generate_project.py': 'ce41dcca87e292a31fcafb2a0655b419f5ef87a97a0b3a5d05eb61e87a2a4d4b'}

class MerchantAftercareEvidenceContracts(unittest.TestCase):
    def setUp(self):
        self.flow=(ROOT/'App/MerchantAftercareEvidenceFlow.swift').read_text()
        self.editor=(ROOT/'App/MerchantBusinessEditor.swift').read_text()
        self.views=(ROOT/'App/MerchantBusinessViews.swift').read_text()
        self.home=(ROOT/'App/MerchantHomeView.swift').read_text()
    def test_exact_inverse_preserves_frozen_decision_filter_note_and_all_other_shared_file_bytes(self):
        for path, proof in INVERSES.items():
            raw=(ROOT/path).read_bytes()
            for offset,after,before in reversed(proof['hunks']):
                self.assertEqual(raw[offset:offset+len(after)],after,path)
                raw=raw[:offset]+before+raw[offset+len(after):]
            self.assertEqual(hashlib.sha256(raw).hexdigest(),proof['base_sha256'],path)
    def test_existing_services_grants_journals_picker_and_root_config_are_unchanged(self):
        for path,sha in PROTECTED.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),sha,path)
    def test_dependencies_come_only_from_existing_workbench_and_owned_editor(self):
        self.assertIn('guard let engagementReader, let exportRecovery else { return nil }',self.home)
        self.assertIn('.init(reader: engagementReader, journal: journal, recovery: exportRecovery)',self.home)
        self.assertIn('editorIsCurrent: { editor?.id == context.id && pendingMutation == nil }',self.views)
        self.assertIn('owner.editorID == context.id, owner.snapshot == snapshot',self.editor)
        self.assertIn('owner.snapshot.document.rows.contains(row)',self.editor)
    def test_exact_owner_source_account_auth_and_raw_draft_fences(self):
        for text in ['document.revision == revision','c.reader.scope == scope','c.reader.authorizationGeneration == authorization',
                     'c.snapshot == snapshot','c.confirmation == nil','!c.isLocked','editorIsCurrent()',
                     'coordinator.reader.scope == owner.scope','coordinator.reader.authorizationGeneration == authorization',
                     'currentDraft() == original','lhs.content.utf8.elementsEqual(rhs.content.utf8)',
                     'lhs.evidence.utf8.elementsEqual(rhs.evidence.utf8)','row.fields["canRespond"]?.bool == true',
                     'mbStrings("allowedDecisions").contains("EVIDENCE")','dependencies.reader.scope == owner.scope']:
            self.assertIn(text,self.flow)
    def test_review_rechecks_exact_refund_access_bytes_and_selected_uuid(self):
        for text in ['review.proof.access.identity == owner.snapshot.access','review.proof.refund == owner.snapshot.document',
                     'refund == refundID, chosen == selection, scope == owner.scope','selectedID == selection.id',
                     'review.command.validateProductionProof(review.proof)','coordinator.review == review',
                     'coordinator.reader.canExecute(review.command, merchantID: owner.snapshot.access.merchantID)',
                     'await self.coordinator.prepare(command)','await self.coordinator.confirm(review)']:
            self.assertIn(text,self.flow)
        self.assertEqual(self.flow.count('await self.coordinator.confirm(review)'),1)
    def test_single_use_consume_occurs_only_after_all_attach_fences_and_no_fallible_apply(self):
        attach=self.flow.split('@discardableResult func attach()',1)[1].split('func retire()',1)[0]
        self.assertLess(attach.index('guard canAttach'),attach.index('takeEvidenceForResponse'))
        self.assertLess(attach.index('takeEvidenceForResponse'),attach.index('applyKey(receipt.objectKey)'))
        self.assertIn('guard canAttach, let expected = matchingReceipt else { return false }',attach)
        for prohibited in ['await ','.prepare(','.confirm(','.execute(','Task {','onReview(']:self.assertNotIn(prohibited,attach)
        self.assertIn('applyKey: { key in evidence = key; issue = nil }',self.editor)
        self.assertEqual(self.flow.count('takeEvidenceForResponse('),1)
    def test_unknown_and_pending_work_cannot_attach_select_or_reenter(self):
        for name,end in [('var canSelect','var review'),('var canAttach','private var matchingReceipt')]:
            block=self.flow.split(name,1)[1].split(end,1)[0]
            self.assertIn('!busy',block);self.assertIn('!coordinator.locked',block)
        self.assertIn('coordinator.failure == nil',self.flow.split('var canAttach',1)[1].split('private var matchingReceipt',1)[0])
        self.assertIn('var busy: Bool { actionPending || coordinator.busy }',self.flow)
        self.assertIn('actionPending = true',self.flow)
    def test_cancel_and_retirement_clear_only_owned_memory_and_preserve_source_draft(self):
        retire=self.flow.rsplit('func retire()',1)[1].split('@MainActor struct MerchantAftercareEvidenceSheet',1)[0]
        for text in ['retired = true','task?.cancel()','selection = nil','uploadReview = nil','coordinator.invalidate()']:self.assertIn(text,retire)
        for prohibited in ['applyKey(','removeItem','unlink','delete','journal.complete','takeEvidenceForResponse']:self.assertNotIn(prohibited,retire)
        for prohibited in ['URLSession','FileManager','UserDefaults','uploadOSS','requestAccess','authorizationStatus','openSettings','cameraSelectionEnabled: true','MerchantEngagementProductionApproval(']:self.assertNotIn(prohibited,self.flow)
    def test_selector_requires_existing_device_gate_and_only_explicit_buttons_open_it(self):
        self.assertIn('reader.permitsDevice(.selectEvidence(refundID), merchantID: owner.snapshot.access.merchantID)',self.flow)
        self.assertIn('Button("merchant.engagement.selectEvidence") { selecting = true }',self.flow)
        self.assertIn('currentScope: { model.canSelect ? model.owner.scope : nil }, nativeSelectionEnabled: model.canSelect',self.flow)
        self.assertNotIn('.task(',self.flow)
    def test_raw_draft_review_owner_scene_and_disappearance_retire_owned_flow(self):
        for text in ['.onChange(of: context.id)','.onChange(of: snapshot)','.onChange(of: aftercareEvidenceDraft)',
                     'if showing { retireEvidenceFlow() }','retireEvidenceFlow()\n                    retireAftercareDecision()']:
            self.assertIn(text,self.editor)
        for text in ['.onChange(of: document.revision)','.onChange(of: document.coordinator.reader.scope)',
                     '.onChange(of: document.coordinator.reader.authorizationGeneration)',
                     '.onChange(of: model.coordinator.reader.scope)', '.onChange(of: model.coordinator.reader.authorizationGeneration)',
                     'if phase != .active { model.retire(); selecting = false }','.onDisappear { model.retire() }']:
            self.assertIn(text,self.flow)
    def test_separate_upload_and_attach_explain_replacement_with_bilingual_fragment(self):
        fragment=json.loads((ROOT/'Resources/MerchantAftercareEvidenceLocalizations.fragment.json').read_text())
        self.assertEqual(len(fragment),7)
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings'];present=set(fragment)&set(catalog)
        if present:
            self.assertEqual(present,set(fragment))
            for key in fragment:self.assertEqual(catalog[key],fragment[key])
        for entry in fragment.values():
            for language in ['en','zh-Hans']:self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())
        self.assertIn('explicitly attach',fragment['merchant.aftercareEvidence.separateResponse']['localizations']['en']['stringUnit']['value'])
        self.assertIn('Cancel keeps the original draft',fragment['merchant.aftercareEvidence.replaceHint']['localizations']['en']['stringUnit']['value'])
        self.assertIn('if model.attach() { dismiss() }',self.flow)
        self.assertIn('Text(model.canAttach ? "merchant.engagement.evidenceReady" : "merchant.business.stale")',self.flow)
    def test_owner_validity_reaches_minted_authorization_through_scoped_reader(self):
        adapter=self.flow.split('private final class MerchantAftercareEvidenceReader',1)[1].split('/// A local bridge',1)[0]
        self.assertIn('var scope: MerchantBusinessScope? { isCurrent ? base.scope : nil }',adapter)
        self.assertIn('owner.isCurrent && currentDraft() == original',adapter)
        self.assertIn('base.authorizationGeneration == authorization',adapter)
        self.assertIn('coordinator = .init(reader: scopedReader, journal: dependencies.journal',self.flow)
        self.assertIn('scopedReader.retire()',self.flow)
        proof=adapter.split('func proof(',1)[1].split('func execute(',1)[0]
        self.assertEqual(proof.count('try requireCommand(command)'),2)
        self.assertLess(proof.index('try requireCommand(command)'),proof.index('await base.proof(command)'))
        self.assertGreater(proof.rindex('try requireCommand(command)'),proof.index('await base.proof(command)'))
    def test_scoped_adapter_composes_existing_execute_check_without_clearing_uncertain_intents(self):
        adapter=self.flow.split('private final class MerchantAftercareEvidenceReader',1)[1].split('/// A local bridge',1)[0]
        execute=adapter.split('func execute(_ review:',1)[1]
        self.assertIn('base.execute(review, authorization: authorization, check:',execute)
        self.assertIn('try self.requireCommand(review.command); try check()',execute)
        self.assertIn('try requireCommand(review.command); return result',execute)
        self.assertIn('throw MerchantBusinessFailure.stale',adapter)
        for prohibited in ['authorization.consume','journal.complete','journal.remove','ProductionApproval(', 'catch {']:
            self.assertNotIn(prohibited,adapter)
if __name__=='__main__':unittest.main(verbosity=2)

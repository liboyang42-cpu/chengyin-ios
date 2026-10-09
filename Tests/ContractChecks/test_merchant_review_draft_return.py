from pathlib import Path
import hashlib,json,os,re,unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):
    p=ROOT/path
    if not p.exists(): p=Path(os.environ['MERCHANT_REVIEW_DRAFT_BASE'])/path
    return p.read_bytes()
BASE_HASHES={'App/MerchantBusinessEditor.swift': '7a4720def304cac5beebc94221fdb55995a00b28a80d56e20d0e7ef964f86424', 'App/MerchantBusinessViews.swift': '5d94dfebc99bb67febee0b42dd562532d443da7bc2b93e50995fd413c6f1cc87'}
INVERSE_BLOCKS={'App/MerchantBusinessEditor.swift': [{'start': 15, 'end': 16, 'after': ['    var reviewInitialContent: String? = nil\n'], 'before': []}, {'start': 19, 'end': 20, 'after': ['    @State private var reviewContentContextID: UUID?\n'], 'before': []}, {'start': 123, 'end': 124, 'after': ['                initializeReviewContent()\n'], 'before': ['                if case .review(let row, .update) = context.kind { content = row.fields.mbText("merchantReply") ?? "" }\n']}, {'start': 126, 'end': 131, 'after': ['    }\n', '    private func initializeReviewContent() {\n', '        guard reviewContentContextID != context.id, case .review(let row, let action) = context.kind else { return }\n', '        reviewContentContextID = context.id\n', '        content = reviewInitialContent ?? (action == .update ? row.fields.mbText("merchantReply") ?? "" : "")\n'], 'before': []}, {'start': 219, 'end': 220, 'after': ['    var editDraft: (() -> Void)? = nil\n'], 'before': []}, {'start': 244, 'end': 249, 'after': ['                if let editDraft {\n', '                    Button("merchant.reviewDraftReturn.edit", action: editDraft).disabled(busy)\n', '                        .accessibilityIdentifier("merchant.reviewDraftReturn.edit")\n', '                        .accessibilityHint(Text("merchant.reviewDraftReturn.hint"))\n', '                }\n'], 'before': []}], 'App/MerchantBusinessViews.swift': [{'start': 206, 'end': 207, 'after': ['    @Environment(\\.scenePhase) private var scenePhase\n'], 'before': []}, {'start': 211, 'end': 212, 'after': ['    @StateObject private var draftReturn: MerchantReviewDraftReturn\n'], 'before': []}, {'start': 226, 'end': 229, 'after': ['        let owner = MerchantBusinessViewModel(reader: reader, journal: journal)\n', '        _query = State(initialValue: query); _model = StateObject(wrappedValue: owner)\n', '        _draftReturn = StateObject(wrappedValue: .init(owner: owner))\n'], 'before': ['        _query = State(initialValue: query); _model = StateObject(wrappedValue: .init(reader: reader, journal: journal))\n']}, {'start': 237, 'end': 238, 'after': ['        let presentedReview = state.confirmation\n'], 'before': []}, {'start': 350, 'end': 352, 'after': ['        .sheet(item: $editor, onDismiss: { draftReturn.discard(); if let mutation = pendingMutation { pendingMutation = nil; if sourcePageCanPrepare(mutation) { model.prepare(mutation) } } }) { context in\n', '            MerchantBusinessEditor(context: context, snapshot: state.snapshot, reviewInitialContent: draftReturn.initialContent(for: context.id), aftercareEvidenceOwner: {\n'], 'before': ['        .sheet(item: $editor, onDismiss: { if let mutation = pendingMutation { pendingMutation = nil; if sourcePageCanPrepare(mutation) { model.prepare(mutation) } } }) { context in\n', '            MerchantBusinessEditor(context: context, snapshot: state.snapshot, aftercareEvidenceOwner: {\n']}, {'start': 355, 'end': 356, 'after': ['                draftReturn.discard()\n'], 'before': []}, {'start': 360, 'end': 364, 'after': ['        .sheet(item: Binding(get: { state.confirmation }, set: { value in\n', '            if value == nil, let presentedReview { draftReturn.cancelReview(id: presentedReview.id) }\n', '        })) { review in\n', '            let capture = draftReturn.capture(review)\n'], 'before': ['        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { model.cancel() } })) { review in\n']}, {'start': 365, 'end': 380, 'after': ['                issue: state.failureKey, cancel: { draftReturn.cancelReview(id: review.id) },\n', '                confirm: {\n', '                    if case .review(_, _, let action, _) = review.mutation, action != .delete {\n', '                        if draftReturn.beginConfirmation(id: review.id) { Task { await model.confirm(review) } }\n', '                    } else { Task { await model.confirm(review) } }\n', '                },\n', '                editDraft: capture.map { captured in { _ = draftReturn.requestReturn(captured) } })\n', '                .onDisappear {\n', '                    if let ticket = draftReturn.didDismiss(reviewID: review.id) {\n', '                        Task {\n', '                            guard let restored = draftReturn.resume(ticket, editorIsVacant: scenePhase == .active && editor == nil && pendingMutation == nil) else { return }\n', '                            editor = restored\n', '                        }\n', '                    }\n', '                }\n'], 'before': ['                issue: state.failureKey, cancel: model.cancel, confirm: { Task { await model.confirm(review) } })\n']}, {'start': 389, 'end': 400, 'after': ['        .onAppear { if scenePhase == .active { draftReturn.activate() } }\n', '        .onChange(of: model.revision) { _, _ in\n', '            if let retired = draftReturn.synchronize(), editor?.id == retired { editor = nil }\n', '        }\n', '        .onChange(of: scenePhase) { _, phase in\n', '            if phase == .active { draftReturn.activate() }\n', '            else if let retired = draftReturn.retire(), editor?.id == retired { editor = nil }\n', '        }\n', '        .onChange(of: reader.scope) { _, _ in draftReturn.retire(); if scenePhase == .active { draftReturn.activate() }; editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }\n', '        .onChange(of: reader.authorizationGeneration) { _, _ in draftReturn.retire(); if scenePhase == .active { draftReturn.activate() }; editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }\n', '        .onDisappear { draftReturn.retire(); editor = nil; pendingMutation = nil; model.invalidate() }\n'], 'before': ['        .onChange(of: reader.scope) { _, _ in editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }\n', '        .onChange(of: reader.authorizationGeneration) { _, _ in editor = nil; pendingMutation = nil; reviewSourceDestination = nil; selection = []; model.invalidate() }\n', '        .onDisappear { editor = nil; pendingMutation = nil; model.invalidate() }\n']}]}
PROTECTED={'Core/MerchantBusinessCoordinator.swift': 'b3977dd4e64edeaa9ecf8b168cf0a6de8ad53bb1a9f8d71ae1099f03dfda9899', 'Core/MerchantBusinessMutation.swift': '4695496ea387604f10c7749f270780472f8a9a39fc20fd712def1b12a7a37b0b', 'Core/MerchantBusinessReading.swift': '906e62610186c515532f1e19898f9ae56bb97652216064415d152978ca4e1c93', 'Core/MerchantBusinessService.swift': '632a5653e3186a41d954c4fd4e01a3928d6c797ad64f08b36624fa8dd97ae5c2', 'Core/MerchantBusinessProduction.swift': 'daa5370b8fe932c520afbcb89e05af85efdc717b525afac464b5d8662832253e', 'Core/MerchantReviewLoadedPages.swift': '1ffa6e8375eb3c037e250454ee723aa77a8c4a33a02bd96baa154cbb746c623c', 'Core/MerchantBusinessDocuments.swift': 'a9ac2f899420fb357103d38cfb78da51a4ca63420fc37e599562ffc05357deb2', 'Core/MerchantBusinessValue.swift': 'c816c7b91d2fd7ed32c518d34211bb74058b1f721bccc595bced0f6c5d0437f1', 'App/MerchantReviewPhotoGallery.swift': 'd61f85d53fcf8696870dc9836330cedaaa15ecb4c3c2a56579d0bebe946220ed', 'App/MerchantBusinessRecordViews.swift': '2f7d3460c1ffdc81f29ab1d4dd5c86ac941dafe204248f7c37940c46f4774bb5', 'App/MerchantOperatorInvitationReceiptView.swift': 'cab6567b0fd9969b1b38f3632d1e786cfcad84de419aab21c6ffb54004749829', 'Core/MerchantOperatorInvitationPresentation.swift': '91de455344f7d34dda4880b507847a5dd1730d8f8224ea377bc2b7dee772bc1a', 'App/MerchantAftercareEvidenceFlow.swift': '55d5c3e7c8cb41b0a436786dd0c0eda441999c8b575e4c34a73dfa9c721ba7ce', 'App/AppSession.swift': '56e188e6c1cf80050ea642a4ebe53a7fd03645d0dda9635ce189b7e9a4d033f0', 'Resources/Localizable.xcstrings': 'b2238724e13da0871b8262d2935b69e3e725964922d6b06ca3bcc2b02e4d7003', 'Questify.xcodeproj/project.pbxproj': 'c96ffd78d97967fd71c4835f99814d4991fd374f74e6a8a0fb9620270dc324dd'}

class ReviewDraftReturnContracts(unittest.TestCase):
    def setUp(self):
        self.flow=read('App/MerchantReviewDraftReturn.swift').decode()
        self.views=read('App/MerchantBusinessViews.swift').decode()
        self.editor=read('App/MerchantBusinessEditor.swift').decode()
    def test_exact_existing_file_inverses_preserve_invitation_gallery_and_other_forms(self):
        for path,blocks in INVERSE_BLOCKS.items():
            lines=read(path).decode().splitlines(keepends=True)
            for b in reversed(blocks):
                self.assertEqual(lines[b['start']:b['end']],b['after'])
                lines[b['start']:b['end']]=b['before']
            self.assertEqual(hashlib.sha256(''.join(lines).encode()).hexdigest(),BASE_HASHES[path])
    def test_core_journal_transport_and_sensitive_features_unchanged(self):
        for path,digest in PROTECTED.items(): self.assertEqual(hashlib.sha256(read(path)).hexdigest(),digest,path)
    def test_only_existing_editable_review_actions_are_captured(self):
        for token in ['case .review(let id, let version, let action, let content)', 'action != .delete', 'case .reviews = review.baseline.document.query', 'try review.mutation.validate(in: review.baseline.document']:
            self.assertIn(token,self.flow)
    def test_exact_current_owner_scope_authorization_access_and_payload(self):
        for token in ['ObjectIdentifier(owner) == ownerID', 'scope.accountID == currentScope.accountID', 'scope.epoch == currentScope.epoch', 'scope.realm.utf8.elementsEqual(currentScope.realm.utf8)', 'c.reader.authorizationGeneration == authorization', 'snapshot.document.query == query', 'Self.fingerprint(snapshot.document.payload) == payload', 'snapshot.access == access', 'snapshot.access.role.utf8.elementsEqual(access.role.utf8)', 'Set(snapshot.access.permissions.map { Data($0.utf8) })', '.sortedKeys', 'SHA256.hash(data: bytes)']:
            self.assertIn(token,self.flow)
    def test_raw_draft_is_never_normalized_or_persisted_by_return(self):
        self.assertIn('nextContent.utf8.elementsEqual(content.utf8)',self.flow)
        self.assertIn('return resumed.content',self.flow)
        for token in ['trimmingCharacters', '.prefix(', 'UserDefaults', 'FileManager', 'URLSession', 'UIPasteboard', 'reader.execute', 'journal.reserve']:
            self.assertNotIn(token,self.flow)
    def test_confirmation_revoked_synchronously_before_handoff(self):
        method=self.flow[self.flow.index('func requestReturn'):self.flow.index('func didDismiss')]
        self.assertLess(method.index('owner.cancel(); discard()'),method.index('pending = .init'))
        self.assertNotIn('Task',method);self.assertNotIn('await',method)
        self.assertIn('owner.revision == capture.ownerRevision',method)
    def test_exact_dismissal_and_one_shot_ticket_guard_queued_work(self):
        for token in ['pending.reviewID == reviewID', 'queued?.id == ticket.id', 'guard editorIsVacant, current(ticket)', 'queued = nil; resumed = ticket', 'owner.revision == ticket.ownerRevision', 'owner.coordinator.confirmation == nil']:
            self.assertIn(token,self.flow)
        self.assertIn('didDismiss(reviewID: review.id)',self.views)
        self.assertIn('editorIsVacant: scenePhase == .active && editor == nil && pendingMutation == nil',self.views)
    def test_confirm_intent_closes_window_before_task_is_launched(self):
        self.assertIn('retiredReviewID = id; discard()',self.flow)
        self.assertIn('review.id != retiredReviewID',self.flow)
        self.assertIn('if draftReturn.beginConfirmation(id: review.id) { Task { await model.confirm(review) } }',self.views)
        self.assertIn('} else { Task { await model.confirm(review) } }',self.views)
    def test_background_departure_and_owner_change_retire(self):
        for token in ['.onChange(of: scenePhase)', 'draftReturn.retire()', '.onChange(of: reader.scope)', '.onChange(of: reader.authorizationGeneration)', '.onDisappear { draftReturn.retire()']:
            self.assertIn(token,self.views)
        self.assertIn('retiredReviewID = owner?.coordinator.confirmation?.id',self.flow)
        self.assertIn('editor?.id == retired { editor = nil }',self.views)
    def test_cancel_keeps_discard_semantics_and_old_callback_cannot_cancel_newer(self):
        self.assertIn('owner.coordinator.confirmation?.id == id',self.flow)
        self.assertIn('discard(); owner.cancel()',self.flow)
        self.assertIn('let presentedReview = state.confirmation',self.views)
        self.assertIn('cancelReview(id: presentedReview.id)',self.views)
        self.assertIn('Button("action.cancel", action: cancel).disabled(busy)',self.editor)
    def test_busy_receipt_unknown_and_failure_are_ineligible(self):
        for token in ['!c.isBusy', '!c.isLocked', 'c.receipt == nil', 'c.failureKey == nil', 'active, ticket.generation == generation']:
            self.assertIn(token,self.flow)
    def test_editor_seeds_once_per_context_with_existing_update_fallback(self):
        for token in ['reviewContentContextID != context.id', 'reviewContentContextID = context.id', 'content = reviewInitialContent ?? (action == .update', 'row.fields.mbText("merchantReply")']:
            self.assertIn(token,self.editor)
        self.assertIn('reviewInitialContent: draftReturn.initialContent(for: context.id)',self.views)
    def test_explicit_accessible_localized_control(self):
        self.assertIn('if let editDraft {',self.editor)
        self.assertIn('Button("merchant.reviewDraftReturn.edit", action: editDraft).disabled(busy)',self.editor)
        self.assertIn('.accessibilityHint(Text("merchant.reviewDraftReturn.hint"))',self.editor)
        strings=json.loads(read('Resources/MerchantReviewDraftReturnLocalizations.fragment.json'))['strings']
        self.assertEqual(set(strings),{'merchant.reviewDraftReturn.edit','merchant.reviewDraftReturn.hint'})
        for item in strings.values():self.assertEqual(set(item['localizations']),{'en','zh-Hans'})
    def test_authored_actual_model_regressions(self):
        tests=read('Tests/AppUnitTests/MerchantReviewDraftReturnTests.swift').decode()
        self.assertEqual(len(re.findall(r'func test',tests)),24)
        for name in ['testUnknownOutcomeDoesNotResurrectDraftOrRemoveJournal','testOldDismissalAndOldQueuedTicketCannotAffectNewerReturn','testExactPayloadBytesRejectCanonicallyEquivalentReplacementWithoutViewRevision','testQueuedConfirmationClosesEditWindowBeforeTaskStarts','testAnotherEditorBlocksAndConsumesQueuedReturn','testBackgroundBeforeEditInvalidatesOldAndFreshCapturesOfSameReview']:
            self.assertIn(name,tests)
    def test_no_timer_automatic_submit_or_focus_side_effect(self):
        for token in ['Timer(', 'Task.sleep', 'DispatchQueue', 'UIAccessibility', 'FocusState', 'UIApplication', 'openURL', 'PhotosPicker']:
            self.assertNotIn(token,self.flow)
if __name__=='__main__': unittest.main()

"""Bounded source contracts only. Does not compile or execute Swift/XCTest."""
from pathlib import Path
import hashlib,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
COORD_BASE="2d02730db4af7d1e3edc571e5aa4a991e50cd4edbf40eb7478cdb42195fd5711"
VIEW_BASE="437dc94ed25b919458d7e931c7fd33508fe1b09b1fba8fcbee258f2581586274"
HELPERS='    public func operatorInvitationCode(id: UUID, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String? {\n        guard let presentation = operatorInvitation, presentation.id == id else { return nil }\n        return presentation.revealedCode(reader: reader, receipt: receipt, now: now, uptime: uptime)\n    }\n    public func operatorInvitationIsCurrent(id: UUID, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {\n        guard let presentation = operatorInvitation, presentation.id == id else { return false }\n        return presentation.isCurrent(reader: reader, receipt: receipt, now: now, uptime: uptime)\n    }\n    public func operatorInvitationAccessMatches(id: UUID, access: MerchantBusinessAccess) -> Bool {\n        guard let presentation = operatorInvitation, presentation.id == id, presentation.matches(receipt) else { return false }\n        return presentation.matchesAccess(access)\n    }\n    public func retireOperatorInvitation(id: UUID) {\n        guard let presentation = operatorInvitation, presentation.id == id else { return }\n        let ownsReceipt = presentation.matches(receipt)\n        presentation.retire(); operatorInvitation = nil\n        // Also remove the original raw response, but never a newer/different receipt.\n        if ownsReceipt { receipt = nil }\n    }\n'
VIEW_HUNK='                    if let invitation = state.operatorInvitation {\n                        MerchantOperatorInvitationReceiptView(owner: model, presentationID: invitation.id)\n                            .id(invitation.id)\n                    }\n'
PROTECTED = dict(zip(
    (
        'Core/MerchantBusinessMutation.swift',
        'Core/MerchantBusinessReading.swift',
        'Core/MerchantBusinessService.swift',
        'Core/MerchantBusinessValue.swift',
        'Core/MerchantBusinessSyntheticFixtures.swift',
        'Core/MerchantOperatorInviteRoute.swift',
        'Core/MerchantMutationFailureDisposition.swift',
        'Core/BusinessRuntimeConfiguration.swift',
        'App/MerchantBusinessEditor.swift',
        'App/AppSession.swift',
        'App/MerchantBusinessAccessModel.swift',
        'App/MerchantOperatorRolePermissionSection.swift',
        'App/MerchantOperatorRosterSections.swift',
        'App/MerchantOperatorInvitationLandingView.swift',
        'Core/MerchantBusinessDocuments.swift',
        'Core/NativeEntryRouting.swift',
        'Core/MerchantBusinessProduction.swift',
        'Core/MerchantBusinessQuery.swift',
    ),
    (
        '4695496ea387604f10c7749f270780472f8a9a39fc20fd712def1b12a7a37b0b',
        '906e62610186c515532f1e19898f9ae56bb97652216064415d152978ca4e1c93',
        '632a5653e3186a41d954c4fd4e01a3928d6c797ad64f08b36624fa8dd97ae5c2',
        'c816c7b91d2fd7ed32c518d34211bb74058b1f721bccc595bced0f6c5d0437f1',
        'e76217e54f944e4caebb100691d2f99e13255fedeec75bf83f19004606c832f2',
        '9941adcfc5d46e1c68b874e16cc85abb31caa8f79aca0a3f419bb78f656c930e',
        '2e1600e8664aff0741dc1c6261d7c480c829db8ec332e567af9ff00019c3b8b7',
        '6c6b0948f358b64fe039c9dbdcefed01ed33d7f97207444185dfdc227be7ba7b',
        '7a4720def304cac5beebc94221fdb55995a00b28a80d56e20d0e7ef964f86424',
        'd6a39320f8978fc5179ce615bf9335a510dd2f3280901e093f2d0187bbb65187',
        'aff601f64622ef1286026eaa9646a6f1b8ebf8f468677a165e0d2a0e1eeb8724',
        '5ca27eb42ef395d7c65bf99af7211c196a7d20f67ac7c66277edfc200f17e8b0',
        'cd18cfd3b2e690d5a1a9b1dba436966401675ea512c58337c9618735bf5ff53c',
        '9a61ab40aa3c1af4dc7ec7c26993dc55a176ca21d33c050566daa7060e5ee88a',
        'a9ac2f899420fb357103d38cfb78da51a4ca63420fc37e599562ffc05357deb2',
        '2b515c95b92e424e05c32ac13f52a28ec46730bfe17953b4ce113eb1a92a6c72',
        'daa5370b8fe932c520afbcb89e05af85efdc717b525afac464b5d8662832253e',
        '8ae347444e61e6d14ad9b981701a0d73f5c6bdad9c52c31a22220a720d25de49',
    ),
))

class OperatorInvitationReceiptContracts(unittest.TestCase):
    def setUp(self):
        self.core=(ROOT/'Core/MerchantOperatorInvitationPresentation.swift').read_text()
        self.coord=(ROOT/'Core/MerchantBusinessCoordinator.swift').read_text()
        self.app=(ROOT/'App/MerchantOperatorInvitationReceiptView.swift').read_text()
    def test_coordinator_inverse_preserves_entire_original_dispatch_and_journal(self):
        text=self.coord
        for hunk,count in [('    public private(set) var operatorInvitation: MerchantOperatorInvitationPresentation?\n',1),
                           ('        operatorInvitation?.retire(); operatorInvitation = nil\n',2),
                           ('            if case .inviteOperator = review.mutation {\n                operatorInvitation = .init(receipt: result, review: review)\n            }\n',1),(HELPERS,1)]:
            self.assertEqual(text.count(hunk),count);text=text.replace(hunk,'')
        self.assertEqual(hashlib.sha256(text.encode()).hexdigest(),COORD_BASE)
    def test_view_inverse_preserves_every_other_merchant_hunk(self):
        text=(ROOT/'App/MerchantBusinessViews.swift').read_text();self.assertEqual(text.count(VIEW_HUNK),1)
        self.assertEqual(hashlib.sha256(text.replace(VIEW_HUNK,'').encode()).hexdigest(),VIEW_BASE)
    def test_services_authority_mutations_recipients_and_editors_unchanged(self):
        for path,digest in PROTECTED.items():self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),digest,path)
    def test_only_acknowledged_current_create_after_journal_completion_mints(self):
        marker='try journal.complete(intent); receipt = result; isLocked = false; snapshot = nil; loadedScope = nil'
        self.assertIn(marker+'\n            if case .inviteOperator = review.mutation {\n                operatorInvitation = .init(receipt: result, review: review)',self.coord)
        self.assertEqual(self.coord.count('operatorInvitation = .init'),1)
        self.assertNotIn('public init(',self.core)
    def test_receipt_validation_uses_original_review_store_role_and_current_owner(self):
        for text in ['scope = review.scope','authorizationGeneration = review.authorizationGeneration','merchantID = review.baseline.access.merchantID',
                     'review.baseline.access.role == "MERCHANT_OWNER"','review.baseline.access.canManageOperators','MerchantBusinessAccess.employeeRoles.contains(role)',
                     'invite["roleCode"]?.string == role','invite["status"]?.string == "PENDING"','invite["version"] == .int(0)',
                     'case .number = identifier','inviteID > 0','reader.scope == scope','reader.authorizationGeneration == authorizationGeneration','reader.canExecute(.inviteOperator(role: roleCode), merchantID: merchantID)']:
            self.assertIn(text,self.core)
    def test_exact_source_token_is_checked_without_signing_trimming_or_generation(self):
        for text in ['value.utf8.count == 43','bytes.count == 32','base64EncodedString()', 'token = parsed?.token'] :self.assertIn(text,self.core)
        for text in ['HMAC<','SymmetricKey','trimmingCharacters','random','UUID().uuidString']:self.assertNotIn(text,self.core)
    def test_expiry_requires_verified_offset_format_without_phone_timezone_fallback(self):
        for text in ['value.utf8.count == 29','\\.000\\+08:00\\z','Locale(identifier: "en_US_POSIX")','Calendar(identifier: .gregorian)',
                     'TimeZone(secondsFromGMT: 8 * 60 * 60)', 'formatter.isLenient = false','formatter.string(from: date) == value','expiry > now','expiry.timeIntervalSince(now) <= 24 * 60 * 60']:
            self.assertIn(text,self.core)
        for text in ['TimeZone.current','Calendar.current','ISO8601DateFormatter','Double(value)']:self.assertNotIn(text,self.core)
    def test_absolute_and_monotonic_expiry_cannot_extend_one_another(self):
        for text in ['maximumPresentationSeconds: TimeInterval = 600','now >= receivedAt','uptime >= receivedUptime','uptime.isFinite',
                     'min(expiresAt.timeIntervalSince(now), Self.maximumPresentationSeconds - (uptime - receivedUptime))']:
            self.assertIn(text,self.core)
        self.assertIn('!metadata.privacyLifetimeIsActive',self.app)
        self.assertIn('metadata.hasValidReceipt && !canReveal',self.app)
    def test_only_explicit_reveal_reads_existing_access_and_has_pre_post_fences(self):
        reveal=self.app[self.app.index('@discardableResult func reveal()'):self.app.index('    func hide()')]
        self.assertEqual(self.app.count('reader.access()'),1)
        self.assertLess(reveal.index('guard canReveal, let owner'),reveal.index('try await owner.coordinator.reader.access()'))
        self.assertIn('guard active, readGeneration == request, !Task.isCancelled, canReveal',reveal)
        self.assertIn('operatorInvitationAccessMatches(id: presentationID, access: access)',reveal)
        self.assertLess(reveal.index('operatorInvitationAccessMatches'),reveal.index('validatedAccess = true; revealed = true'))
        self.assertIn('Task { _ = await model.reveal() }',self.app)
        timer=self.app[self.app.index('        .task {'):];self.assertNotIn('reader.access()',timer);self.assertNotIn('model.reveal()',timer)
    def test_access_failure_denies_display_and_retry_is_explicit(self):
        self.assertIn('private var validatedAccess = false',self.app)
        self.assertIn('guard active, revealed, validatedAccess else { return nil }',self.app)
        self.assertIn('issue = "merchant.operatorInvite.accessFailed"; return false',self.app)
        self.assertIn('func hide() { readGeneration = UUID(); busy = false; validatedAccess = false; revealed = false }',self.app)
        self.assertIn('current == access && current.role == "MERCHANT_OWNER" && current.canManageOperators',self.core)
        self.assertIn('.utf8.elementsEqual((access.name ?? "").utf8)',self.core)
    def test_retirement_clears_only_exact_receipt_and_never_touches_journal(self):
        retire=self.coord[self.coord.index('    public func retireOperatorInvitation'):self.coord.index('    private func set')]
        self.assertIn('presentation.id == id',retire);self.assertIn('let ownsReceipt = presentation.matches(receipt)',retire)
        self.assertIn('if ownsReceipt { receipt = nil }',retire)
        for text in ['journal.', 'isLocked =','requestID','await ']:self.assertNotIn(text,retire)
        self.assertIn('retired = true; token = nil',self.core)
        self.assertIn('Data(SHA256.hash(data: bytes))',self.core)
        self.assertIn('encoder.outputFormatting = [.sortedKeys]',self.core)
    def test_scene_departure_hide_and_expired_models_cannot_revive(self):
        for text in ['guard active else { return }','active = false; readGeneration = UUID()',
                     'owner?.coordinator.retireOperatorInvitation(id: presentationID)',
                     '.onChange(of: scenePhase) { _, phase in if phase != .active { model.retire() } }','.onDisappear { model.retire() }']:
            self.assertIn(text,self.app)
        self.assertIn('.id(invitation.id)',(ROOT/'App/MerchantBusinessViews.swift').read_text())
    def test_code_is_memory_only_without_route_clipboard_sharing_or_new_grants(self):
        for text in ['UserDefaults','FileManager','URLSession','UIPasteboard','ShareLink','UIActivityViewController','openURL','https://','requestAccess','HMAC<','Keychain','JSONDecoder']:
            self.assertNotIn(text,self.app+self.core)
        self.assertNotRegex(self.app+self.core,r'\bprint\s*\(')
        self.assertNotIn('.execute(',self.app);self.assertNotIn('.prepare(',self.app)
        self.assertIn('Text(verbatim: code)',self.app);self.assertIn('.textSelection(.enabled).privacySensitive()',self.app)
        self.assertNotIn('private var token',self.app)
    def test_metadata_and_invalid_acknowledgment_are_truthful(self):
        for text in ['String(metadata.merchantID)','metadata.roleName ?? metadata.roleCode','String(inviteID)','value: expiry','if metadata.hasValidReceipt','merchant.operatorInvite.unavailable']:
            self.assertIn(text,self.app)
        self.assertIn('hasValidReceipt = parsed != nil',self.core)
        self.assertIn('receiptFingerprint = Self.fingerprint(receipt)',self.core)
    def test_localizations_cover_actual_labels_and_sensitive_code_has_no_fake_key(self):
        fragment=json.loads((ROOT/'Resources/MerchantOperatorInvitationReceiptLocalizations.fragment.json').read_text())
        keys=set(re.findall(r'merchant\.operatorInvite\.[A-Za-z]+',self.app))-{'merchant.operatorInvite.code'}
        self.assertEqual(set(fragment),keys);self.assertEqual(len(fragment),12)
        for entry in fragment.values():self.assertEqual(set(entry['localizations']),{'en','zh-Hans'})
        self.assertIn('invitation was created',fragment['merchant.operatorInvite.unavailable']['localizations']['en']['stringUnit']['value'])
        self.assertIn('intended person',fragment['merchant.operatorInvite.warning']['localizations']['en']['stringUnit']['value'])
    def test_authored_core_tests_cover_source_format_and_unknown_journal_preservation(self):
        tests=(ROOT/'Tests/CoreTests/MerchantOperatorInvitationPresentationTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',tests)),23)
        for text in ['testPhoneTimeZoneDoesNotReinterpretSourceExpiry','testUnknownCreateOutcomeNeverMintsOrRetriesInvitation',
                     'testJournalCompletionFailureCannotMintPresentation','testOwnerChangeDuringCreateCannotPublishReceipt',
                     'testOldInvitationRetirementCannotClearAcknowledgedRevokeReceipt']:
            self.assertIn(text,tests)
    def test_authored_app_tests_cover_suspended_read_replacement_and_no_automatic_requests(self):
        tests=(ROOT/'Tests/AppUnitTests/MerchantOperatorInvitationReceiptTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',tests)),25)
        for text in ['testInitialReceiptAndTimerNeverReadOrRevealAutomatically','testSuspendedReadOwnerChangeWithoutManualRetirementCannotReveal',
                     'testSuspendedReadReplacedReceiptCannotRevealOrClearNewerReceipt','testSuspendedReadExpiryCannotRevealAndClearsOriginalReceipt',
                     'testOldReceiptRetirementCannotReconcileNewUnknownWrite','testInvalidReceiptHasNoUnboundedRawTokenLifetime',
                     'testRetiredOldModelCannotReviveAfterSameOwnerReturnOrClearNewReceipt']:
            self.assertIn(text,tests)

    def test_definite_access_loss_and_cancelled_error_retire_but_network_failure_can_retry(self):
        catch=self.app[self.app.index('        } catch {'):self.app.index('    func hide()')]
        for text in ['guard !Task.isCancelled, canReveal else { retire(); return false }','error is CancellationError',
                     'failure == .denied','failure == .stale','failure == .disabled','error as? APIError == .unauthorized','error as? APIError == .notConfigured']:
            self.assertIn(text,catch)
        self.assertLess(catch.index('retire(); return false'),catch.index('issue = "merchant.operatorInvite.accessFailed"'))
        tests=(ROOT/'Tests/AppUnitTests/MerchantOperatorInvitationReceiptTests.swift').read_text()
        for text in ['testSuspendedDefiniteAccessLossWithUnchangedScopePermanentlyRetiresOldReceipt',
                     'testCancelledSuspendedReadWithNetworkErrorRetiresInsteadOfOfferingRetry',
                     'testContextLossWhileFailedReadIsSuspendedCannotReviveAfterReturn',
                     'testFailedReadKeepsCodeHiddenAndDoesNotAutomaticallyRetry']:
            self.assertIn(text,tests)

if __name__=='__main__':unittest.main(verbosity=2)

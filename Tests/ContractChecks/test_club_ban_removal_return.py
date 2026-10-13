"""Source contracts only; Swift and actual host lifecycle are not executed."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubBanRemovalReturnContracts(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_existing_unban_entry_is_operation_specific(self):
        view = self.text('App/ClubGovernanceViews.swift')
        self.assertIn('if self.operation == .bans, operation == .unban {', view)
        self.assertIn('bansSource == banRemovalSource', view)
        self.assertIn('scope == nil || scope == self.scope', view)
        self.assertIn('banRemovalReturn.open(seed: seed, source: bansSource', view)
        self.assertIn('row["sourceType"] == .string("CLUB"), row["status"] == .string("ACTIVE")', view)
    def test_exact_unban_target_has_no_member_picker_or_new_grant(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        for part in ['Set(seed.keys) == Set(["banId", "version"])', '$0["sourceType"] == .string("CLUB")', '$0["status"] == .string("ACTIVE")', 'ClubGovernanceFormRoute(operation: .unban', 'review.command.fields["banId"] == expected.route.seed["banId"]', 'review.command.fields["version"] == expected.route.seed["version"]']:
            self.assertIn(part, code)
        for absent in ['.assignRole', '.transferOwner', 'MemberPicker', 'access.send(', 'coordinator.confirm(', 'Date()']:
            self.assertNotIn(absent, code)
    def test_current_source_revalidates_reader_authority_and_typed_list(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        for part in ['context.operation == .bans, context.accepts(snapshot)', 'context.identity == access.identity', 'context.authorizationGeneration == access.authorizationGeneration', 'context.accessIdentity == ObjectIdentifier(access)', 'ClubGovernanceRead.bans.permission', 'ClubGovernanceValidation.validate(snapshot.value, operation: .bans']:
            self.assertIn(part, code)
    def test_begin_binds_review_request_namespace_and_unchanged_target_row(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        for part in ['state == .reviewing', 'review.command.operation == .unban', 'review.identity == expected.source.context.identity', 'review.authorizationGeneration == expected.source.context.authorizationGeneration', 'review.storageNamespace == expected.source.namespace, review.journalRealm == expected.source.realm', 'Set(["clubId", "banId", "version", "reason", "requestId"])', 'review.snapshot.value.array?.contains(row) == true', 'submitted = review']:
            self.assertIn(part, code)
    def test_only_matching_acknowledged_state_closes(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        self.assertIn('state == .acknowledged, submitted == review', code)
        self.assertIn('acknowledged = true; isPresented = false', code)
        self.assertIn('if acknowledged { didDismiss = true } else { retire() }', code)
    def test_original_single_confirmation_and_optional_callback(self):
        code = self.text('App/ClubGovernanceCommandForm.swift')
        self.assertEqual(code.count('try await coordinator.confirm(review)'), 1)
        self.assertIn('route.operation == .unban && banRemovalReturn?.begin(review) == true', code)
        self.assertIn('if returnsToBans { banRemovalReturn?.acknowledged(review, value) }', code)
        self.assertIn('receipt = value; self.review = nil; locked = true', code)
    def test_concrete_non_nil_owner_binding_fences_old_callback(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        for part in ['item?.id == expected.id && attachment == expected.attachment', 'owner.binding(item, source: source, active: active)', 'owner.dismissed(item, source: source(), active: active())', 'guard owner.isPresented, owner.current(item, source: source(), active: active())']:
            self.assertIn(part, code)
        self.assertIn('if let item = banRemovalReturn.item', self.text('App/ClubGovernanceViews.swift'))
    def test_return_consumed_only_once_when_current_and_visible(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        for part in ['guard visible, active, !isPresented, didDismiss, acknowledged, let item', 'retire(); readTicket = ticket', 'readTicket == expected && expected.source.context == context', 'if readTicket == expected { readTicket = nil }']:
            self.assertIn(part, code)
    def test_read_admission_and_all_await_fences_include_specific_owner(self):
        code = self.text('App/ClubGovernanceViews.swift')
        self.assertIn('operation != .bans || !banReads.loading', code)
        self.assertEqual(code.count('banReadIsCurrent(banAttachment), access.identity == expected'), 3)
        self.assertIn('result = try await banReads.load(context: context, access: access, check: check)', code)
        self.assertIn('banRemovalSource == ticket.source, !Task.isCancelled', code)
    def test_read_context_change_and_actual_departure_retire_inflight_owner(self):
        code = self.text('App/ClubGovernanceViews.swift')
        self.assertIn('if banReads.synchronize(readContext)', code)
        self.assertIn('banRemovalReturn.retire(); invalidateRead(); loading = false', code)
        self.assertIn('banRemovalReturn.depart(attachment, reads: banReads) { generation &+= 1; loading = false }', code)
        owner = self.text('App/ClubBanRemovalReturn.swift')
        self.assertIn('guard attachment == expected else { return }', owner)
        self.assertIn('depart(expected); reads.retire(); resetParentRead()', owner)
    def test_foreground_refresh_is_current_visible_and_not_a_write(self):
        code = self.text('App/ClubGovernanceViews.swift')
        self.assertIn('else { Task { await loadBansIfNeeded() } }', code)
        self.assertIn('guard operation == .bans, banRemovalReturn.visible, scenePhase == .active', code)
        self.assertIn('!banRemovalReturn.retainsReturn, !banReads.loading', code)
        self.assertIn('snapshotContext != readContext || snapshotGeneration != generation', code)
    def test_existing_lock_and_service_contract_unchanged_in_natural_flow(self):
        code = self.text('App/ClubBanRemovalReturn.swift')
        self.assertNotIn('snapshot = receipt', code)
        self.assertNotIn('locked.remove', code)
        self.assertIn('try await access.read(.bans, scope: expected.scope, options: [:], check: current)', code)
    def test_unknown_injection_is_send_only_and_native_departure_uses_host_method(self):
        code = self.text('Tests/AppUnitTests/ClubBanRemovalReturnTests.swift')
        self.assertIn('access.sendFailure = .unknown(message: nil)', code)
        self.assertIn('access.readFailure = .forbidden', code)
        self.assertIn('owner.depart(attachment, reads: reader) { resets += 1 }', code)
        self.assertIn('XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))', code)

if __name__ == '__main__': unittest.main()

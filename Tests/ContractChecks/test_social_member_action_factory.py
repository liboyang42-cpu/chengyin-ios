"""Source checks only; Swift/Apple execution is a separate gate."""
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class SocialMemberActionFactoryContracts(unittest.TestCase):
 def read(self, p): return (ROOT/p).read_text()
 def test_normal_app_factory_and_defaults(self):
  app=self.read('App/AppSession.swift'); deps=self.read('App/NativeRuntimeDependencies.swift')
  self.assertIn('var socialActionAccess: any SocialActionAccess { socialMemberActions.access }',app)
  self.assertIn('var socialActionCoordinator: SocialActionCoordinator { socialMemberActions.coordinator }',app)
  self.assertIn('SocialMemberActionSessionOwner(configuration:',app)
  self.assertIn('return self.runtimeDependencies.socialMemberActionApprovals',app)
  self.assertIn('socialMemberActionApprovals: [SocialMemberActionApproval] = []',deps)
  self.assertIn('composition.storage.operationJournal()',app)
 def test_session_owner_rebuilds_exact_scope_and_permanently_revokes_escaped_pairs(self):
  owner=self.read('Core/SocialMemberActionSessionOwner.swift'); app=self.read('App/AppSession.swift')
  for fragment in ['let context: RuntimeDependencyContext?', 'let identity: SocialAccountIdentity',
                   'previous.lease.active = false', 'self.scope == captured', 'captured.context.map(approvals) ?? []',
                   'SocialActionCoordinator(access: access)']:
   self.assertIn(fragment,owner)
  self.assertNotIn('journal.clear',owner)
  self.assertNotIn('OperationEndpointApproval(',owner)
  self.assertNotIn('lazy var socialActionAccess',app)
  self.assertNotIn('lazy var socialActionCoordinator',app)
  self.assertIn('gate = SessionOperationGate() { didSet { retainedSocialMemberActions?.synchronizeSession()',app)
  self.assertIn('guard !committingAuthenticatedSession, let regionalConfiguration',app)
 def test_routes_are_only_source_bound_member_actions(self):
  value=self.read('Core/SocialMemberActionFactory.swift')
  self.assertEqual(set(re.findall(r'"(api/[^" ]+)"',value)),{'api/user/follow/action','api/user/public-info','api/im/start','api/im/conversations'})
  self.assertIn('default: return nil',value)
  self.assertIn('endpoint.paths == operation.paths',value)
  self.assertIn('market == .china',value)
  self.assertIn('now < expiresAt',value)
 def test_review_bound_to_full_context_and_transport_fenced(self):
  value=self.read('Core/SocialMemberActionFactory.swift'); contracts=self.read('Core/SocialActionContracts.swift')
  for fragment in ['snapshot.memberContext == captured','current() == context','approval.matches(context, now: now())','request.httpMethod == "POST"','request.value(forHTTPHeaderField: "Authorization") == context.session.token']:
   self.assertIn(fragment,value)
  self.assertIn('memberContext == other.memberContext',contracts)
  self.assertIn('let result = try await transport.send(request)\n            try check()',value)
  self.assertIn('try check()\n            throw error',value)
 def test_durable_unknown_and_authoritative_readback(self):
  value=self.read('Core/SocialMemberActionFactory.swift')
  for fragment in ['try journal.write(record)','try journal.clear(record)','fresh.isFollowed == !before','$0.id == id && $0.kind == .direct && $0.counterparty?.id == member','throw SocialActionWriteFailure.outcomeUnknown']:
   self.assertIn(fragment,value)
  self.assertLess(value.index('try journal.write(record)'),value.index('let receipt = try await SocialActionService'))
  self.assertNotIn('retry(',value)
 def test_approved_ui_is_per_command_and_preserves_square_generation(self):
  value=self.read('App/SocialActionViews.swift'); factory=self.read('Core/SocialMemberActionFactory.swift')
  self.assertIn('coordinator.availability(for: review.command, target: review.target) == .approved',value)
  self.assertIn('fallback.snapshot(target: target, generation: generation)',factory)
  self.assertIn('records[key]?.state == .submitting',self.read('Core/SocialActionCoordinator.swift'))
 def test_follow_uses_explicit_desired_state(self):
  value=self.read('Core/SocialActionContracts.swift')
  self.assertIn('"follow": followed ? "0" : "1"',value)
 def test_native_tests_exercise_normal_factory_and_late_scope_changes(self):
  tests=self.read('Tests/CoreTests/SocialMemberActionFactoryTests.swift')
  self.assertIn('SocialMemberActionFactory.make(',tests)
  self.assertIn('testRoleOrNamespaceChangeDuringFinalReadbackNeverAcknowledges',tests)
  self.assertIn('testTokenChangeBetweenReviewAndConfirmInvalidatesExactReview',tests)
  self.assertIn('AppSession(runtimeDependencies: dependencies)',self.read('Tests/AppUnitTests/SocialMemberActionAppTests.swift'))
if __name__=='__main__': unittest.main()

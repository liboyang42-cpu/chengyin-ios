"""Bounded source contracts only; AppUnit and Apple navigation execution are separate."""
import pathlib,json,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class TicketWalletTeamContracts(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.ui=(ROOT/'App/TicketWalletTeamView.swift').read_text()
  cls.wallet=(ROOT/'App/TicketWalletView.swift').read_text()
  cls.detail=(ROOT/'App/TicketWalletDetailView.swift').read_text()
  cls.context=cls.ui.split('struct TicketWalletTeamContext:',1)[1].split('@MainActor struct TicketWalletTeamEntryState',1)[0]
  cls.model=cls.ui.split('@MainActor @Observable final class TicketWalletTeamModel',1)[1].split('@MainActor struct TicketWalletTeamView:',1)[0]
 def test_existing_host_factory_only_flows_to_fresh_ticket_section(self):
  self.assertIn('lifecycleCoordinator: orderLifecycleCoordinator, makeTeamCoordinator: makeTeamCoordinator)',self.wallet)
  self.assertIn('var makeTeamCoordinator: (() -> TeamCoordinator)? = nil',self.detail)
  self.assertLess(self.detail.index('else if let ticket = model.value(owner: key), ticket.id == id {'),self.detail.index('TicketWalletTeamEntrySection('))
  self.assertIn('TeamHomeView(coordinator: makeTeamCoordinator(), makeCoordinator: makeTeamCoordinator)',self.wallet)
 def test_ticket_owner_requires_positive_explicit_type_and_rejects_conflicting_ids(self):
  for value in ['requestedID > 0','ticket.id == requestedID','ownerID > 0','let ownerType = ticket.ownerType','switch ownerType',
                'ticket.activityID == nil, ticket.topicID == nil || ticket.topicID == ownerID','ticket.topicID == nil, ticket.activityID == nil || ticket.activityID == ownerID','default: return nil']:
   self.assertIn(value,self.context)
  for forbidden in ['title','productType','purchaseKind','registrationStatus','payableAmount']:
   self.assertNotIn(forbidden,self.context)
 def test_only_explicit_selected_navigation_constructs_coordinator(self):
  self.assertEqual(self.ui.count('coordinator: makeCoordinator()'),1)
  nav=self.ui.split('.navigationDestination(item: $entry.target)',1)[1].split('/// Isolated',1)[0]
  self.assertIn('if entry.matches(target, context: context, reader: reader)',nav)
  self.assertIn('coordinator: makeCoordinator()',nav)
  entry=self.ui.split('@MainActor struct TicketWalletTeamEntrySection:',1)[1].split('/// Isolated',1)[0]
  self.assertNotIn('loadTeams(',entry)
 def test_presentation_and_exact_reader_owner_guard_navigation(self):
  for value in ['self.presentationID == presentationID','target.owner == TicketWalletReadOwner(reader: reader, id: target.context.registrationID)',
                '.onChange(of: TicketWalletReadOwner(reader: reader, id: requestedID))','mutating func disappear() { visible = false; presentationID = UUID() }']:
   self.assertIn(value,self.ui)
 def test_lookup_uses_existing_coordinator_without_new_service_or_authority(self):
  self.assertIn('await coordinator.loadTeams()',self.model)
  self.assertIn('await coordinator.loadDetail(.id(team.id), requireMembership: true)',self.model)
  for forbidden in ['TeamCoordinator(', 'TeamReadOnlyService(', 'TeamHTTPService(', 'ReadApproval(', 'TeamAction.', '.prepare(', '.submit(', 'currentSession:']:
   self.assertNotIn(forbidden,self.model)
 def test_exact_owner_and_known_active_statuses_filter_without_silent_first_match(self):
  self.assertIn('team.walletEligible && team.ownerKey == owner',self.context)
  self.assertIn('let matches = coordinator.teams.filter(context.includes)',self.model)
  self.assertIn('Set(matches.map(\\.id)).count == matches.count',self.model)
  self.assertIn('rows = matches; loaded = true',self.model)
  self.assertNotIn('.first',self.model)
  self.assertNotIn('.sorted',self.model)
 def test_only_verified_list_rows_can_issue_detail_and_fresh_membership_is_required(self):
  self.assertGreaterEqual(self.model.count('loaded, rows.contains(team), context.includes(team)'),2)
  for value in ['value.team.id == team.id','value.joined == true','context.includes(value.team)','detail = value']:
   self.assertIn(value,self.model)
 def test_failed_or_denied_lookup_does_not_claim_empty_team_list(self):
  self.assertIn('guard coordinator.messageKey == nil else { issue = .failed; return }',self.model)
  self.assertIn('model.loaded && model.rows.isEmpty && model.issue == nil',self.ui)
  self.assertIn('guard coordinator.messageKey == nil, let value = coordinator.detail else { issue = .failed; return }',self.model)
 def test_source_reader_and_team_session_scope_are_checked_before_and_at_receipt(self):
  for value in ['coordinator.synchronizeSession()', 'coordinator.scope == teamScope && coordinator.authenticated',
                'owner == TicketWalletReadOwner(reader: reader, id: context.registrationID)',
                'guard active(permit), generation == request else { return }']:
   self.assertIn(value,self.model)
  self.assertEqual(self.model.count('guard active(permit), generation == request else { return }'),2)
 def test_departure_cancels_actual_tasks_and_captured_permits_block_queued_retries(self):
  for value in ['task?.cancel(); task = nil; presentation = nil; generation = UUID(); coordinator.leaveScreen()',
                'let offeredPresentation = model.presentation', '.onDisappear { visible = false; model.end() }',
                'model.scheduleList(offeredPresentation)', 'await withTaskCancellationHandler { await pending.value } onCancel: { pending.cancel() }']:
   self.assertIn(value,self.ui)
 def test_readonly_roster_has_no_membership_or_financial_mutation(self):
  self.assertIn('TeamMemberRow(member: member, remove: nil)',self.ui)
  self.assertIn('Text("team.ticketSeparation")',self.ui)
  for forbidden in ['TeamReviewSheet(', 'TeamInvitePreview(', 'TeamDetailView(', 'actionButton(', 'URLSession', 'api/', 'UserDefaults', 'Keychain', 'AsyncImage(', '.join(', '.leave(', '.disband(']:
   self.assertNotIn(forbidden,self.ui)
 def test_existing_detail_lifecycle_and_play_destination_remain_present(self):
  for value in ['model.accepts(presentation, currentOwner: key)', 'playReadOwner == playProvider.owner',
                'playEntry.matches(target, ticket: ticket, requestedID: id, reader: reader, provider: playProvider)',
                'let destination = playProvider.destination(target: target, reader: reader)']:
   self.assertIn(value,self.detail)
 def test_localizations_cover_new_literal_keys_bilingually(self):
  fragment=json.loads((ROOT/'Resources/TicketWalletTeamLocalizations.fragment.json').read_text())
  rendered=re.sub(r'\.accessibilityIdentifier\("[^\"]*"\)','',self.ui)
  keys=set(re.findall(r'"(ticketTeam\.[A-Za-z]+)"',rendered))
  self.assertEqual(keys,set(fragment))
  for value in fragment.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
 def test_real_workflow_tests_are_authored_for_matching_membership_lifetime_and_no_writes(self):
  tests=(ROOT/'Tests/AppUnitTests/TicketWalletTeamTests.swift').read_text()
  for name in ['testOwnedTeamLookupUsesExactOwnerAndKnownActiveStatesPreservingMultipleMatches','testChangedOwnerStatusIdOrMembershipNeverPublishesRoster',
               'testFreshJoinedExactTeamDetailIsRequiredAndNoWritesArePossible','testQueuedLookupAfterDepartureAndOldPermitAfterReopenCannotDispatch',
               'testLateTicketReaderChangeOrTeamSessionChangeCannotPublish','testFailedReadCannotClaimNoTeamAndExplicitRetryCanReturnSuccessfulEmpty']:
   self.assertIn('func '+name,tests)
if __name__=='__main__':unittest.main()

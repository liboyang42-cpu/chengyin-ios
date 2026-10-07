"""Creator proposal source checks only; not Swift, Apple runtime or live legal acceptance."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(name): return (ROOT / name).read_text()
class CreatorPendingContracts(unittest.TestCase):
 def test_author_is_exact_twenty_one_without_owner_or_consent_fields(self):
  text=read('Core/WorkshopCreatorPendingContracts.swift').split('enum CodingKeys:',1)[1].split('public init(',1)[0]
  fields=set(re.findall(r'\b\w+\b',' '.join(re.findall(r'^\s*case (.+)$',text,re.M))))
  self.assertEqual(fields,set('requestId sourceTemplateId expectedTemplateHash expectedPackageContentHash termsDocument commercialUse adaptation translation allowedRegions buyerKinds themeLimit merchantLimit runLimit priceMinor currency expiresAt useDuration updates redistribution copyrightOwnership acquisition'.split()))
 def test_only_author_list_detail_routes_are_exposed(self):
  s=read('Core/WorkshopCreatorPendingService.swift');self.assertIn('case author, list, detail',s);self.assertNotIn('case status',s)
  self.assertIn('guard route != .author',s);self.assertIn('try confirmation.consume()',s);self.assertIn('request.httpBody == body',s)
 def test_three_grants_are_separate_and_nil_by_default(self):
  s=read('App/AppCompositionRoot.swift')
  for kind in ['Author','List','Detail']:
   self.assertIn('workshopCreatorPending'+kind+'Approval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPending'+kind+'Approval? = { _ in nil }',s)
  self.assertIn('route != .author',s);self.assertIn('sendWorkshopCreatorPendingAuthor',s)
 def test_full_command_strictly_read_back_before_confirmation_and_dispatch(self):
  s=read('Core/WorkshopCreatorPendingController.swift')
  self.assertIn('WorkshopCreatorPendingWire.decode(Record.self',s);self.assertIn('try WorkshopCreatorWire.encode(record) == data',s)
  self.assertLess(s.index('try store.retain(command); pending = command'),s.index('let confirmation = WorkshopCreatorPendingConfirmation'))
  self.assertIn('return offerDispatch(pending, a)',s);self.assertIn('try old.data() == command.data()',s)
 def test_historical_metadata_cannot_create_target(self):
  s=read('Core/WorkshopCreatorPendingController.swift');start=s.index('self.receipt = receipt');end=s.index('public func offerAnotherProposal',start);part=s[start:end]
  self.assertIn('self.preview = nil; self.items = []',part);self.assertIn('try await self.refresh(life)',part);self.assertNotIn('declarationTarget',part)
 def test_detail_selection_is_current_preview_and_full_revision_cas(self):
  s=read('Core/WorkshopCreatorPendingController.swift');p=s[s.index('public func offerReview'):s.index('public func offerBackToProposals')]
  self.assertLess(p.index('previewService.preview'),p.index('service.detail'))
  self.assertIn('targetId: item.targetId, expectedRevision: item.revision',p);self.assertIn('detail.metadata == item',p);self.assertIn('detail.matches(preview: preview',p)
 def test_ordinary_owned_shelf_enters_author_form_not_static_descriptor(self):
  s=read('App/WorkshopCreatorConsentView.swift').split('@MainActor struct WorkshopCreatorConsentView:',1)[0]
  self.assertIn('makeWorkshopCreatorPendingController',s);self.assertIn('WorkshopCreatorPendingView',s)
  self.assertIn('WorkshopCreatorConsentSelection(source: id)',read('App/TemplateAuthoringMineView.swift'))
 def test_legal_text_and_structured_choices_are_visible(self):
  s=read('App/WorkshopCreatorConsentView.swift')
  for value in ['target.termsDocument','detail.proposedOffer.priceMinor','detail.proposedOffer.currency','detail.proposedOffer.buyerKinds','detail.proposedOffer.terms.allowedRegions','detail.proposedOffer.terms.themeLimit','detail.proposedOffer.terms.runLimit']:
   self.assertIn(value,s)
  self.assertIn('acknowledgments = []',read('Core/WorkshopCreatorConsentController.swift'))
 def test_form_choices_start_blank_and_fixed_restrictions_are_disclosed(self):
  s=read('Core/WorkshopCreatorPendingController.swift').split('@MainActor public final class',1)[0]
  self.assertIn('termsDocument = "", commercialUse = "", adaptation = "", translation = ""',s)
  strings=json.loads(read('Resources/WorkshopCreatorPending.xcstrings'))['strings']
  for item in strings.values():self.assertEqual(set(item['localizations']),{'en','zh-Hans'})
  self.assertIn('PAID',strings['workshopPending.fixedRestrictions']['localizations']['en']['stringUnit']['value'])
 def test_currentness_configuration_and_scope_are_fenced(self):
  s=read('App/AppSession.swift');self.assertIn('workshopCreatorPendingBinding.invalidate(); workshopCreatorConsentBinding.invalidate(); workshopCreatorConfigurationChanging = true',s)
  for kind in ['Author','List','Detail']:self.assertIn('self.currentWorkshopCreatorPending'+kind+'?.revision',s)
  c=read('Core/WorkshopCreatorPendingController.swift');self.assertIn('context.session.namespace',c);self.assertIn('String(sourceTemplateId)',c);self.assertIn('declaration?.invalidate()',c)
 def test_complete_core_app_and_ui_cases_are_authored(self):
  for path,minimum in [('Tests/CoreTests/WorkshopCreatorPendingCoreTests.swift',15),('Tests/CoreTests/WorkshopCreatorPendingControllerTests.swift',14),('Tests/AppUnitTests/WorkshopCreatorPendingNormalFlowTests.swift',12),('Tests/AppUITests/WorkshopCreatorPendingEntryFlowTests.swift',1),('Tests/AppUITests/WorkshopCreatorPendingReviewFlowTests.swift',1),('Tests/AppUITests/WorkshopCreatorPendingRecoveryFlowTests.swift',1)]:
   self.assertGreaterEqual(len(re.findall(r'func test\w+\(',read(path))),minimum)
 def test_author_review_transition_uses_stable_outer_screen_identity(self):
  s=read('App/WorkshopCreatorPendingView.swift').split('var body: some View {',1)[1]
  self.assertLess(s.index('VStack(spacing: 0)'),s.index('if controller.phase == .reviewing'))
  self.assertNotIn('Group {',s.split('@ViewBuilder',1)[0])
  self.assertIn('testHostedAuthorToReviewTransitionKeepsTheSameAppearanceLive',read('Tests/AppUnitTests/WorkshopCreatorPendingNormalFlowTests.swift'))
 def test_existing_declaration_history_precedes_current_proposal_gates(self):
  s=read('Core/WorkshopCreatorPendingController.swift');start=s.index('public func offerLoad');end=s.index('private func refresh',start);s=s[start:end]
  self.assertLess(s.index('declarationStore?.load()'),s.index('canReadProposals()'))
  self.assertLess(s.index('previewService.status'),s.index('self.refresh(life)'))
  self.assertIn('let available = read != nil',read('App/AppSession.swift'))
  self.assertIn('Historical receipt only.',read('Resources/WorkshopCreatorPending.xcstrings'))
 def test_creator_labels_use_explicit_named_tables_and_selected_locale(self):
  helper=read('App/WorkshopCreatorLocalization.swift')
  self.assertIn('table = "WorkshopCreatorPending"',helper);self.assertIn('table = "WorkshopCreatorConsent"',helper)
  self.assertIn('table: table, locale: locale',helper)
  for path in ['App/WorkshopCreatorConsentView.swift','App/WorkshopCreatorPendingView.swift']:
   s=read(path);self.assertIn('workshopCreatorLocalized(key, locale: locale)',s)
   self.assertNotRegex(s,r'\b(?:Text|Button|Section|Toggle|LabeledContent|ProgressView|navigationTitle)\("workshop(?:Creator|Pending)\.')
   self.assertNotIn('LocalizedStringKey(',s)
  self.assertIn('Button(workshopCreatorLocalized("workshopCreator.open", locale: creatorLocale))',read('App/TemplateAuthoringMineView.swift'))
  self.assertIn('testEveryCreatorLabelUsesItsNamedCatalogAndSelectedLanguage',read('Tests/AppUnitTests/WorkshopCreatorPendingNormalFlowTests.swift'))
 def test_fixture_stays_debug_and_does_not_register_a_network_client(self):
  for path in ['App/WorkshopCreatorPendingFixtureData.swift','App/WorkshopCreatorPendingFixtureSupport.swift']:
   s=read(path);self.assertTrue(s.startswith('#if DEBUG'));self.assertNotIn('URLSession',s)
if __name__=='__main__':unittest.main()

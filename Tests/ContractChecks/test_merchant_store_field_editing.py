import json,unittest
from pathlib import Path
R=Path(__file__).resolve().parents[2]
class Contract(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.core=(R/'Core/MerchantStoreFieldDraft.swift').read_text();cls.session=(R/'App/MerchantStoreFieldSession.swift').read_text();cls.view=(R/'App/MerchantStoreFieldEntry.swift').read_text()
 def test_exact_six_source_fields(self):self.assertIn('case name, preference, description, derivativeBenefits, slogan, cityRole',self.core)
 def test_destination_specific_fields(self):
  for s in ['case .profile(let p)','case .decor(let d)','case .story(let s): return self == .description','default: return nil']:self.assertIn(s,self.core)
 def test_source_utf16_limits(self):
  self.assertIn('self == .description ? 300 : 100',self.core);self.assertIn('value.utf16.count > field.limit',self.core)
 def test_name_required_without_rewriting_raw_input(self):
  self.assertIn('field == .name, value.unicodeScalars.allSatisfy({ Self.nameWhitespace.contains($0) })',self.core)
  self.assertNotIn('value = value.trimming',self.core);self.assertIn('buffer.value = raw',self.session)
 def test_unchanged_historical_and_nil_are_noop(self):
  self.assertIn('guard isDirty else { return nil }',self.core);self.assertIn('guard isDirty else { return source }',self.core)
  self.assertIn('p.derivativeBenefits ?? ""',self.core)
 def test_apply_only_one_field_in_correct_variant(self):
  for s in ['p.name = value','p.preference = value','p.description = value','p.derivativeBenefits = value','d.slogan = value','d.cityRole = value','s.profile.description = value']:self.assertIn(s,self.core)
  for s in ['p.website =','p.derivatives =','d.tags =','d.categoryID =','s.cooperation =']:self.assertNotIn(s,self.core)
 def test_full_raw_sibling_comparison(self):
  for s in ['Data($0.utf8)','x.businessTimeReplacement','x.derivativeBenefits','x.coverImage','x.serviceTag','x.serviceText','x.gallery + x.tags','x.cooperation.suitActivityTypes','x.cooperation.clearsCapacity']:self.assertIn(s,self.core)
 def test_owner_generation_and_original_baseline_fences(self):
  for s in ['document.revision == revision','c.reader.scope == scope','c.draftIdentity == identity','sameDraft(draft, original)','sameDraft(baseline, self.baseline)','presentationIsCurrent()']:self.assertIn(s,self.session)
 def test_existing_auth_review_lock_and_destination(self):
  for s in ['c.reader.isConfigured','c.reader.isAuthenticated','c.isCurrent','!c.isBusy','!c.isLocked','c.confirmation == nil','draft.destination == c.destination','baseline.destination == c.destination']:self.assertIn(s,self.session)
 def test_single_consumption_before_owner_stage(self):
  s=self.session[self.session.index('func apply()'):];self.assertLess(s.index('cancel()'),s.index('document.edit(next)'))
 def test_dirty_close_keep_and_discard(self):
  for s in ['if buffer.isDirty { asksDiscard = true; return false }','guard isCurrent, asksDiscard else { return }; asksDiscard = false','guard isCurrent, !asksDiscard else','buffer.value = ""']:self.assertIn(s,self.session)
 def test_old_presentation_binding_and_permit_rejected(self):
  for s in ['generation == permit','self.generation == captured','guard session?.id == id else','self.session?.id == shownID','self?.close(shownID)']:self.assertIn(s,self.session)
 def test_lifecycle_clears_new_buffer(self):
  for s in ['.onChange(of: document.revision)','.onChange(of: document.coordinator.draftIdentity)','.onChange(of: document.coordinator.reader.scope)','.onChange(of: scenePhase)','.onDisappear { presentation.deactivate() }','.privacySensitive()']:self.assertIn(s,self.view)
 def test_discard_prompt_not_consumed_by_framework_binding(self):
  self.assertIn('Binding(get: { session.asksDiscard }, set: { _ in })',self.view)
  self.assertIn('.interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)',self.view)
 def test_no_new_io_or_write_capability(self):
  for s in ['URLSession','UserDefaults','UIPasteboard','.load(','.prepare(','.confirm(','.save(','.document(','.access(','.grant','canSave =']:self.assertNotIn(s,self.core+self.session+self.view)
 def test_bilingual_keys(self):
  rows=json.loads((R/'Resources/MerchantStoreFieldLocalizations.fragment.json').read_text());self.assertEqual(len(rows),16)
  for v in rows.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
 def test_native_test_modules_and_inventory(self):
  for p,n,module in [('CoreTests/MerchantStoreFieldDraftTests.swift',17,'QuestifyCore'),('AppUnitTests/MerchantStoreFieldSessionTests.swift',22,'Questify'),('AppUITests/MerchantStoreFieldFlowTests.swift',5,None)]:
   s=(R/'Tests'/p).read_text();self.assertEqual(s.count('func test'),n)
   if module:self.assertIn('@testable import '+module+'\n',s)
 def test_existing_fixture_only_no_new_runtime_injection(self):
  ui=(R/'Tests/AppUITests/MerchantStoreFieldFlowTests.swift').read_text();self.assertIn('--uitesting-merchant-operations-fixture',ui)
  self.assertNotIn('merchant.operations.confirm',ui);self.assertNotIn('Fixture',self.session+self.view)
if __name__=='__main__':unittest.main()

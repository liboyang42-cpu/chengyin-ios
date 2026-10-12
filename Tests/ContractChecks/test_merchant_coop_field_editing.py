import unittest,json
from pathlib import Path
R=Path(__file__).resolve().parents[2]
class Contract(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.core=(R/'Core/MerchantCoopFieldDraft.swift').read_text();cls.session=(R/'App/MerchantCoopFieldSession.swift').read_text();cls.view=(R/'App/MerchantCoopFieldEntry.swift').read_text()
 def test_exact_three_source_fields(self):
  self.assertIn('case capacity, availableTime, demand',self.core)
  self.assertIn('MerchantCoopField(rawValue: fieldID)',self.view)
 def test_input_never_normalized_or_silently_truncated(self):
  for s in ['trimmingCharacters','lowercased','prefix(','.removeLast(']:self.assertNotIn(s,self.core+self.session)
  self.assertIn('buffer.value = text',self.session)
 def test_source_field_limits_and_capacity_domain(self):
  for s in ['self == .demand ? 500 : 100','value.utf16.count > field.limit','(48...57).contains($0)','Int(value) == nil','!value.isEmpty']:self.assertIn(s,self.core)
 def test_only_selected_field_is_applied(self):
  for s in ['result.capacity = value','result.availableTime = value','result.demand = value']:self.assertIn(s,self.core)
  for s in ['result.chargeType =','result.suitActivityTypes =','result.coopOpen =','acknowledgeCapacityEdit']:self.assertNotIn(s,self.core+self.session)
 def test_raw_utf8_dirty_and_freshness(self):
  self.assertIn('!value.utf8.elementsEqual(original.utf8)',self.core)
  for s in ['a.capacity.utf8.elementsEqual(b.capacity.utf8)','a.availableTime.utf8.elementsEqual(b.availableTime.utf8)','a.demand.utf8.elementsEqual(b.demand.utf8)','Data($0.utf8)','a.clearsCapacity == b.clearsCapacity']:self.assertIn(s,self.core)
 def test_unchanged_legacy_no_op(self):
  self.assertIn('guard isDirty else { return nil }',self.core);self.assertIn('guard isDirty else { return settings }',self.core)
  self.assertIn('if changed { document.edit(.cooperation(next)) }',self.session)
 def test_owner_and_baseline_fences(self):
  for s in ['document.revision == revision','c.reader.scope == scope','c.draftIdentity == identity','sameValues(value, original)','sameValues(base, baseline)','c.reader.isConfigured','c.reader.isAuthenticated','!c.isBusy','!c.isLocked','c.confirmation == nil']:self.assertIn(s,self.session)
 def test_no_read_or_write_operation_or_new_capability(self):
  for s in ['URLSession','UIPasteboard','UserDefaults','.access()', '.document(','.load(','.prepare(','.confirm(','.save', 'OperationEndpointApproval','upload','grant']:self.assertNotIn(s,self.core+self.session+self.view)
 def test_consumes_before_existing_local_edit(self):
  start=self.session.index('func apply()');s=self.session[start:]
  self.assertLess(s.index('cancel()'),s.index('document.edit(.cooperation(next))'))
 def test_dirty_close_preserves_buffer_until_user_choice(self):
  self.assertIn('if buffer.isDirty { asksDiscard = true; return false }',self.session)
  self.assertIn('func keepEditing() { guard isCurrent, asksDiscard else { return }; asksDiscard = false }',self.session)
  self.assertIn('buffer.value = ""',self.session)
 def test_alert_callbacks_do_not_preconsume_choice(self):
  self.assertIn('Binding(get: { session.asksDiscard }, set: { _ in })',self.view)
  self.assertIn('if session.discard() { close() }',self.view);self.assertIn('{ session.keepEditing() }',self.view)
 def test_dirty_interactive_dismiss_requires_explicit_cancel(self):
  self.assertIn('.interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)',self.view)
  self.assertIn('if session.requestClose() { close() }',self.view)
 def test_old_route_cannot_close_replacement(self):
  self.assertIn('let shownID = route?.id',self.view);self.assertIn('guard route?.id == id else { return }',self.view)
  self.assertIn('close(selected.id)',self.view)
 def test_lifecycle_retires_buffer(self):
  for s in ['.onChange(of: document.revision)','.onChange(of: document.coordinator.draftIdentity)','.onChange(of: document.coordinator.reader.scope)','.onChange(of: scenePhase)','.onDisappear { retire() }','.privacySensitive()']:self.assertIn(s,self.view)
 def test_bilingual_new_keys(self):
  v=json.loads((R/'Resources/MerchantCoopFieldLocalizations.fragment.json').read_text());self.assertEqual(len(v),9)
  for item in v.values():self.assertEqual(set(item['localizations']),{'en','zh-Hans'})
 def test_existing_fixture_used_without_new_route(self):
  v=(R/'Tests/AppUITests/MerchantCoopFieldFlowTests.swift').read_text()
  self.assertIn('--uitesting-merchant-operations-fixture',v);self.assertIn('merchant.operations.entry.merchant.operations.cooperation',v)
  self.assertNotIn('merchant.operations.confirm',v)
 def test_native_test_inventory_and_stale_sequences(self):
  for p,n in [('CoreTests/MerchantCoopFieldDraftTests.swift',12),('AppUnitTests/MerchantCoopFieldSessionTests.swift',22),('AppUITests/MerchantCoopFieldFlowTests.swift',5)]:self.assertEqual((R/'Tests'/p).read_text().count('func test'),n)
  t=(R/'Tests/AppUnitTests/MerchantCoopFieldSessionTests.swift').read_text()
  for s in ['testDirtyCancelThenKeepEditing','testCanceledOldSession','testExistingReadOnlyComposition','testExistingPendingWriteLock','testReviewInProgress','testCanonicalSiblingChange']:self.assertIn(s,t)
if __name__=='__main__':unittest.main()

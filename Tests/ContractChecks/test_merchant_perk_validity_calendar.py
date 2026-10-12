from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
class CalendarContracts(unittest.TestCase):
 @classmethod
 def setUpClass(c):
  c.core=(R/'Core/MerchantPerkValidityDraft.swift').read_text();c.app=(R/'App/MerchantPerkValidityCalendar.swift').read_text();c.host=(R/'App/CooperationFlowEditors.swift').read_text();c.workbench=(R/'App/CooperationFlowWorkbench.swift').read_text()
 def test_fixed_source_timezone(self):self.assertIn('TimeZone(secondsFromGMT: 8 * 60 * 60)!',self.core)
 def test_source_day_only_wire(self):self.assertIn('f.dateFormat = "yyyy-MM-dd"',self.core);self.assertIn('f.isLenient = false',self.core)
 def test_tomorrow_in_source_calendar(self):self.assertIn('calendar.startOfDay(for: now)',self.core);self.assertIn('date(byAdding: .day, value: 1',self.core)
 def test_apply_rechecks_current_clock(self):self.assertIn('func apply(now: Date = Date())',self.app);self.assertIn('day >= Self.minimum(now: now)',self.core)
 def test_old_values_not_implicitly_repaired(self):self.assertIn('guard edited else { return original }',self.core)
 def test_clear_remains_optional_string(self):self.assertIn('guard enabled else { return "" }',self.core);self.assertIn('validEnd: validEnd.isEmpty ? nil : validEnd',self.host)
 def test_all_sibling_form_fields_fenced(self):self.assertIn('siblingFields: [name, String(type), retail, cost, quota]',self.host)
 def test_scope_and_raw_bytes(self):self.assertIn('lhs.session == rhs.session',self.app);self.assertIn('Data(lhs.value.utf8)',self.app);self.assertIn('lhs.siblingFields.map { Data($0.utf8) }',self.app)
 def test_dirty_keep_discard(self):
  for x in ['if draft.isDirty { asksDiscard = true','func keepEditing()','session.cancel(); close()','.interactiveDismissDisabled(session.draft.isDirty)']:self.assertIn(x,self.app)
 def test_once_only_apply(self):self.assertIn('let value = try draft.value(now: now); cancel(); return value',self.app)
 def test_stale_callback_bound_to_id(self):self.assertIn('guard session?.id == shown.id',self.app);self.assertIn('guard session?.id == shownID',self.app)
 def test_background_retires_picker(self):self.assertIn('phase != .active { session?.cancel(); session = nil }',self.app)
 def test_normal_workbench_entry(self):self.assertIn('CoopFlowTemplateEditor(currentCalendarSession: { reader.session })',self.workbench)
 def test_actual_editor_field_wired(self):self.assertIn('MerchantPerkValidityEntry(value: $validEnd',self.host)
 def test_result_is_local(self):self.assertIn('value = next; appliedValue = next; appliedContext = context()',self.app)
 def test_no_service_or_write_added(self):
  for x in ['URLSession','perform(','sendRequest','CoopFlowService(', 'permitsDispatch']:self.assertNotIn(x,self.app+self.core)
 def test_disabled_submit_policy_preserved(self):self.assertIn('Button("coopflow.submit") {}.disabled(true)',self.host)
if __name__=='__main__':unittest.main()

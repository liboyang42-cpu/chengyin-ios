import pathlib,unittest,json
R=pathlib.Path(__file__).resolve().parents[2]
class MerchantPerkValiditySubmissionContract(unittest.TestCase):
 def setUp(self):
  self.core=(R/'Core/CooperationFlowContracts.swift').read_text();self.draft=(R/'Core/MerchantPerkValidityDraft.swift').read_text();self.ui=(R/'App/CooperationFlowEditors.swift').read_text()
 def test_only_create_wire_branch_validates_current_clock(self):
  self.assertIn('public func body(now: Date = Date())',self.core)
  self.assertIn('case .createTemplate(let f):\n            try MerchantPerkValidityDraft.validateForCreation(f.validEnd, now: now)',self.core)
  self.assertEqual(self.core.count('validateForCreation('),1)
 def test_history_constructor_has_no_today_rule(self):
  body=self.core.split('public struct CoopFlowPerkTemplate:',1)[1].split('public enum CoopFlowMutation:',1)[0]
  self.assertNotIn('validateForCreation',body);self.assertNotIn('Date()',body);self.assertIn('formatter.string(from: date) == validEnd',body)
 def test_untouched_calendar_value_stays_exact(self):
  self.assertIn('guard edited else { return original }',self.draft)
  self.assertIn('guard enabled else { return "" }',self.draft)
  self.assertIn('guard day >= Self.minimum(now: now)',self.draft)
 def test_creation_nil_allowed_but_day_must_reach_tomorrow(self):
  s=self.draft.split('public static func validateForCreation',1)[1].split('public mutating',1)[0]
  self.assertIn('guard let value else { return }',s);self.assertIn('day >= minimum(now: now)',s)
  self.assertIn('TimeZone(secondsFromGMT: 8 * 60 * 60)',self.draft)
 def test_normal_editor_tap_checks_before_navigation_and_reports_error(self):
  s=self.ui.split('struct CoopFlowTemplateEditor:',1)[1].split('struct CoopFlowReasonEditor:',1)[0]
  self.assertLess(s.index('_ = try operation.body()'),s.index('showingReview = true'))
  self.assertIn('catch { validityIssue = true }',s);self.assertIn('merchant.perkSubmission.invalidDate',s)
  self.assertIn('MerchantPerkValidityEntry(value: $validEnd',s);self.assertIn('TextField("coopflow.field.validEnd", text: $validEnd)',s)
 def test_submit_gate_and_bilingual_error_present(self):
  self.assertIn('Button("coopflow.submit") {}.disabled(true)',self.ui)
  fragment=json.loads((R/'Resources/MerchantPerkValiditySubmissionLocalizations.fragment.json').read_text())
  self.assertEqual(set(fragment['merchant.perkSubmission.invalidDate']['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()

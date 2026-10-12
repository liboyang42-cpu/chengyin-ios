from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
class ContactFlowContracts(unittest.TestCase):
 @classmethod
 def setUpClass(c):
  c.selection=(R/'Core/MerchantCustomerContactSelection.swift').read_text();c.reader=(R/'App/SessionMerchantCustomerContact.swift').read_text();c.flow=(R/'App/MerchantCustomerContactFlow.swift').read_text();c.entry=(R/'App/MerchantCustomerContactEntry.swift').read_text();c.host=(R/'App/MerchantBusinessViews.swift').read_text()
 def test_exact_source_commands(self):
  self.assertIn('.contact(customerID, purpose)',self.selection);self.assertIn('MerchantContactPurpose.allCases',self.entry)
 def test_returned_customer_only(self):
  self.assertIn('snapshot.document.rows.contains(record)',self.selection);self.assertIn('record.kind == .customer',self.selection)
 def test_masked_source_only(self):self.assertIn('case .maskedPhone = contact',self.selection)
 def test_permissions_not_inferred(self):
  for k in ['merchant:crm:read','merchant:crm:sensitive:read']:self.assertIn(k,self.selection)
 def test_source_snapshot_and_authorization(self):
  for s in ['self.scope == scope','self.authorizationGeneration == authorizationGeneration','self.snapshot == snapshot']:self.assertIn(s,self.selection)
 def test_current_owner_checks(self):
  for s in ['state.isCurrent','!state.isBusy','!state.isLocked','state.failureKey == nil','acceptedOwner.coordinator']:self.assertIn(s,self.entry)
 def test_no_manual_identifier(self):self.assertNotIn('TextField',self.entry+self.flow)
 def test_no_new_production_grant(self):
  for s in ['MerchantEngagementProductionApproval(', 'URLSession(', 'sendRequest(', 'UIPasteboard', 'tel:']:self.assertNotIn(s,self.entry+self.flow+self.reader)
 def test_narrowed_scope_and_command(self):
  for s in ['base.scope == selection.scope','command == selection.command','merchantID == selection.merchantID']:self.assertIn(s,self.reader)
 def test_existing_ticket_required(self):
  self.assertIn('base.execute(review, authorization: authorization',self.reader);self.assertIn('try self.check(review.command); try externalCheck()',self.reader)
 def test_fresh_proof_each_review(self):self.assertIn('await coordinator.prepare(selection.command)',self.flow);self.assertIn('await coordinator.confirm(review)',self.flow)
 def test_no_sensitive_phone_render_or_storage(self):
  self.assertNotIn('contact.phone',self.flow);self.assertNotIn('UserDefaults',self.flow+self.reader);self.assertNotIn('phone:',self.selection)
 def test_device_grant_required(self):self.assertIn('reader.permitsDevice(.contact(selection.customerID, selection.purpose)',self.flow)
 def test_existing_one_shot_consumption(self):self.assertIn('await coordinator.consumeContact(using: delivery)',self.flow)
 def test_background_and_close_retire(self):self.assertIn('phase != .active { flow.invalidate() }',self.flow);self.assertIn('lease.active = false; coordinator.invalidate()',self.flow)
 def test_real_host_registration(self):self.assertIn('MerchantCustomerContactEntry(owner: model, record: row)',self.host);self.assertIn('.merchantCustomerContactFactory',(R/'App/QuestifyApp.swift').read_text())
if __name__=='__main__':unittest.main()

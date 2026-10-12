import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class ContactStableOwnerContract(unittest.TestCase):
 def test_row_borrows_flow_without_sheet(self):
  s=(ROOT/'App/MerchantCustomerContactEntry.swift').read_text().split('/// Retained by MerchantBusinessPage')[0]
  self.assertIn('@Binding var flow:',s)
  for x in ['@State','.sheet(','.onDisappear']:self.assertNotIn(x,s)
 def test_stable_host_and_old_dismissal_guard(self):
  s=(ROOT/'App/MerchantCustomerContactEntry.swift').read_text().split('/// Retained by MerchantBusinessPage')[1]
  for x in ['content.background','.id(flow?.id)','flow?.id == shownID ? flow : nil','guard flow?.id == shownID else { return }','.onDisappear { flow?.invalidate(); flow = nil }','let captured = flow','captured?.reconcile()']:self.assertIn(x,s)
 def test_normal_page_injects_same_owner(self):
  s=(ROOT/'App/MerchantBusinessViews.swift').read_text()
  for x in ['@State private var customerContactFlow: MerchantCustomerContactFlow?','MerchantCustomerContactEntry(owner: model, record: row, flow: $customerContactFlow)', '.modifier(MerchantCustomerContactStablePresentation(owner: model, flow: $customerContactFlow))']:self.assertIn(x,s)
if __name__=='__main__':unittest.main()

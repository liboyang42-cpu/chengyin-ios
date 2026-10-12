import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class CustomerClearFiltersContract(unittest.TestCase):
 def test_normal_entry_and_existing_refresh(self):
  s=(ROOT/'App/MerchantBusinessViews.swift').read_text()
  for token in ['merchant.business.customers.clearFilters','customerFilterDraft.hasWorkspaceFilters || applied.hasWorkspaceFilters','let cleared = renderedDraft.clearingWorkspaceFilters()','query = .customers(customerFilterDraft); selection = []; Task { await reload() }']:self.assertIn(token,s)
 def test_old_context_cannot_clear_new_edits(self):
  s=(ROOT/'App/MerchantBusinessViews.swift').read_text()
  for token in ['state.snapshot == expected','reader.scope == renderedScope','reader.authorizationGeneration == renderedAuthorization','customerFilterDraft == renderedDraft','scenePhase == .active, state.isCurrent, !state.isBusy, !state.isLocked']:self.assertIn(token,s)
 def test_clear_does_not_touch_search_or_permissions(self):
  s=(ROOT/'Core/MerchantBusinessQuery.swift').read_text().split('public func clearingWorkspaceFilters()')[1].split('public func validate()')[0]
  for token in ['keyword =','permissions','URLSession','sendRequest']:self.assertNotIn(token,s)
if __name__=='__main__':unittest.main()

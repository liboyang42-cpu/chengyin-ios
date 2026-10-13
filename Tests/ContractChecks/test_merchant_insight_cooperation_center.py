import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class InsightCooperationCenterContract(unittest.TestCase):
 def test_stale_button_cannot_navigate(self):
  s=(ROOT/'App/MerchantMarketingView.swift').read_text().split('Button("merchant.insightCooperationCenter.open")')[1].split('}.accessibilityIdentifier')[0]
  for t in ['scenePhase == .active','model.service.scope == scope','!model.busy','model.failure == nil','model.insight == insight','recommendationOrigin == origin','loadedRecommendationOrigin == origin','onSuggestion(.cooperationCenter(origin))']:self.assertIn(t,s)
 def test_normal_host_uses_existing_read_and_current_merchant(self):
  s=(ROOT/'App/NativeEntryLandingView.swift').read_text().split('case .cooperationCenter(let origin):')[1].split('case .cooperationSettings')[0]
  for t in ['session.merchantOperationsReader.isAuthenticated','session.merchantOperationsReader.scope == origin.readerScope','query: .recruiting','focusedMerchantID: origin.merchantID']:self.assertIn(t,s)
  for t in ['ProjectEditView','prepare(','execute(','confirm(']:self.assertNotIn(t,s)
 def test_origin_is_checked_on_destination_and_no_recommendation_id_needed(self):
  s=(ROOT/'App/MerchantMarketingView.swift').read_text();self.assertIn('case .cooperationCenter(let origin) = route, origin != recommendationOrigin',s)
  block=s.split('Section("merchantMarketing.recommendedTopics")')[1].split('Section("merchantMarketing.recommendedPartners")')[0]
  self.assertIn('merchant.insightCooperationCenter.open',block);self.assertNotIn('recommendedTopics.isEmpty',block)
if __name__=='__main__':unittest.main()

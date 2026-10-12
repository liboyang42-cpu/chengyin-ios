import pathlib,unittest,json
R=pathlib.Path(__file__).resolve().parents[2]
class CooperationInboxTopicContract(unittest.TestCase):
 def setUp(self):
  self.core=(R/'Core/CooperationInboxTopicFilter.swift').read_text();self.ui=(R/'App/CooperationBrowserView.swift').read_text()
 def test_normal_existing_inbox_has_selector_and_clear(self):
  self.assertIn('topicFilterSection(snapshot)',self.ui);self.assertIn('cooperation.topicFilter.choose',self.ui);self.assertIn('cooperation.topicFilter.clear',self.ui)
 def test_all_three_sections_filter_before_render_without_replacing_models(self):
  self.assertEqual(self.ui.count('CooperationInboxTopicFilter.visibleRows('),3)
  self.assertIn('ForEach(rows, id: \\.offset)',self.ui);self.assertEqual(self.ui.count('ForEach(visible, id: \\.offset)'),2)
  self.assertIn('rows.enumerated().filter',self.core)
 def test_choices_require_loaded_topic_and_matching_reader_scope(self):
  self.assertIn('Self.options(in: inbox).contains(where: { $0.id == topicID })',self.core)
  self.assertIn('self.owner == owner && self.scope == scope',self.core)
  self.assertIn('ObjectIdentifier(reader) == owner, reader.scope == scope',self.ui)
  self.assertIn('.onChange(of: reader.isAuthenticated)',self.ui)
 def test_partial_errors_and_pagination_are_not_hidden(self):
  self.assertEqual(self.ui.count('case .failure(let issue): CooperationIssueView(issue: issue)'),3)
  self.assertIn('if snapshot.isPartial',self.ui);self.assertIn('if page.hasMore == true',self.ui)
 def test_existing_detail_and_candidate_routes_retained(self):
  self.assertIn('CooperationInviteDetailView(key: CooperationInviteKey(id: row.id, direction: direction), reader: reader, peerReader: peerReader)',self.ui)
  self.assertIn('CooperationCandidateLink(topicID: row.topicId, reader: reader)',self.ui)
  self.assertIn('CooperationCandidateLink(topicID: topic, reader: reader)',self.ui)
 def test_selection_does_not_trigger_io_or_reset_navigation(self):
  section=self.ui.split('private func topicFilterSection',1)[1].split('private func invitationSection',1)[0]
  for value in ['.inbox(','.detail(','.pool(','.candidates(','URLSession','Task {'] :self.assertNotIn(value,section)
  self.assertNotIn('.onChange(of: direction)',self.ui)
  for value in ['HTTPTransport','UserDefaults','URLSession','.execute(','requestID']:self.assertNotIn(value,self.core)
 def test_bilingual_scope_and_empty_state(self):
  rows=json.loads((R/'Resources/CooperationInboxTopicFilterLocalizations.fragment.json').read_text());self.assertEqual(len(rows),6)
  for row in rows.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()

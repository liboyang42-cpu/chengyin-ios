from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[2]
class PlacePickerContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def test_01_existing_route_only(self):
  s=self.read('Core/SearchMapService.swift');a=s[s.index('    public func cityNodes('):s.index('    /// Only the activity layer')]
  self.assertEqual(a.count('get("api/city/nodes"'),1);self.assertNotIn('activity',a);self.assertNotIn('form(',a)
 def test_02_legacy_city_search_keeps_filter_and_dedup(self):
  s=self.read('Core/SearchMapService.swift');self.assertIn('self.cityNodes(query, token: token).filter { $0.coordinate != nil }',s);self.assertIn('nodes: unique(nodeResult.rows, by: { $0.id })',s);self.assertIn('async let activities = attemptActivityPage',s)
 def test_03_reader_default_denies_and_session_requires_current_approval(self):
  s=self.read('Core/SearchMapReading.swift');self.assertIn('func cityNodes(_ query: CityNodeSearchQuery) async throws -> [SearchMapCityNode] { throw APIError.notConfigured }',s);self.assertIn('guard currentContext().manualMapApprovalRevision != nil',s);self.assertIn('return try await read { try await $0.cityNodes(query, token: $1) }',s)
 def test_04_core_preserves_exact_draft(self):
  s=self.read('Core/ProjectNodePlaceSelection.swift');self.assertIn('ProjectEditPendingMaterials.exactData(draft) == bytes',s);self.assertIn('Data(draft.chapters[ci].id.utf8) == Data(chapterID.utf8)',s);self.assertIn('(draft.pendingMaterials ?? []).contains',s);self.assertIn('"locationRequired"] == .bool(false)',s)
 def test_05_apply_only_chosen_coordinates(self):
  s=self.read('Core/ProjectNodePlaceSelection.swift');self.assertIn('let coordinate = poi.coordinate',s);self.assertNotIn('RoamSearchArea',s);self.assertNotIn('merchantID',s);self.assertNotIn('templateID',s);self.assertIn('.name.isEmpty',s);self.assertIn('Double(next.latitude) != coordinate.latitude',s)
 def test_06_explicit_actions_only(self):
  s=self.read('App/ProjectNodePlacePicker.swift');self.assertIn('Task { await controller.search(original, action: action) }',s);self.assertNotIn('.task',s);self.assertNotIn('CLLocation',s);self.assertIn('controller.apply(original)',s);self.assertIn('controller.close(original)',s)
 def test_07_owner_reader_and_aba(self):
  s=self.read('App/ProjectNodePlacePicker.swift');self.assertIn('ObjectIdentifier(model), reader: reader.map(ObjectIdentifier.init)',s);self.assertIn('model.draftMutationRevision == value.revision',s);self.assertIn('model.isCurrentStarterLease(value.lease)',s);self.assertIn('reader?.scope == value.scope',s)
 def test_08_async_query_area_and_cancel_fences(self):
  s=self.read('App/ProjectNodePlacePicker.swift');self.assertIn('requestID == ticket && input == capturedInput && reader.manualAreaRevision == areaRevision',s);self.assertIn('resultsAreaRevision == reader?.manualAreaRevision',s);self.assertIn('!Task.isCancelled',s);self.assertIn('opening?.id == original.id',s)
 def test_09_invalid_rows_are_not_silently_dropped(self):
  s=self.read('App/ProjectNodePlacePicker.swift');self.assertIn('rows = result',s);self.assertIn('!ProjectNodePlaceSelection.permits(row)',s);self.assertIn('Set(result.map(\\.id)).count == result.count',s)
 def test_10_current_saved_node_mount(self):
  s=self.read('App/ProjectEditDetailForms.swift');mount='ProjectNodePlacePickerEntry(model: model, chapterID: chapterID, nodeID: nodeID)';self.assertEqual(s.count(mount),1);self.assertIn('if allowsGameplayRemoval ?? (chapterOverride == nil && starterLease == nil) {\n                '+mount,s)
 def test_11_reader_injection_does_not_create_authority(self):
  s=self.read('App/QuestifyApp.swift');self.assertIn('.environment(\\.projectNodePlaceReader, session.searchMapReader)',s);self.assertNotIn('ManualMapReadApproval(',s)
 def test_12_named_bilingual_catalog(self):
  rows=json.loads(self.read('Resources/ProjectNodePlacePicker.xcstrings'))['strings'];self.assertEqual(len(rows),14)
  for key,value in rows.items():self.assertEqual(set(value['localizations']),{'en','zh-Hans'});self.assertIn('"'+key+'"',self.read('App/ProjectNodePlacePicker.swift'))
 def test_13_exact_utf8_input_equality(self):
  s=self.read('App/ProjectNodePlacePicker.swift')
  for field in ['latitude','longitude','keyword']:self.assertIn('Data(a.'+field+'.utf8) == Data(b.'+field+'.utf8)',s)
 def test_14_search_captured_synchronously_and_consumed_once(self):
  s=self.read('App/ProjectNodePlacePicker.swift');self.assertIn('let action = controller.captureSearch(original); Task',s);self.assertIn('action.generation == requestID',s);self.assertIn('action.openingID == original.id',s);self.assertIn('action.input == input',s)
if __name__=='__main__':unittest.main()

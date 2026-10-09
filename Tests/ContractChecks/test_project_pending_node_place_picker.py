from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PendingPlaceContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def test_explicit_target_kind(self):
  s=self.read('App/ProjectPendingNodePlacePicker.swift');self.assertIn('case saved(ProjectNodePlaceSelection)',s);self.assertIn('case pending(ProjectPendingNodePlaceCapture)',s)
 def test_staged_binding_only(self):
  s=self.read('App/ProjectPendingNodePlacePicker.swift');s=s[s.index('@MainActor struct ProjectPendingNodePlaceContext'):];self.assertIn('context.controller.node(for: context.destination).wrappedValue = next',s);self.assertNotIn('persistLocalChange',s);self.assertNotIn('saveLocal',s);self.assertNotIn('model.draft =',s)
 def test_exact_candidate_and_draft_revision(self):
  s=self.read('App/ProjectPendingNodePlacePicker.swift');self.assertIn('context.controller.candidateRevision == revision',s);self.assertIn('exactData(context.controller.candidate) == bytes',s);self.assertIn('exactData(model.draft) == draft',s);self.assertIn('context.controller.model === model',s)
 def test_destination_and_alias_guards(self):
  s=self.read('App/ProjectPendingNodePlacePicker.swift');self.assertIn('destination.kind == .edit',s);self.assertIn('controller.isCurrent(destination)',s);self.assertIn('Data(controller.candidate.id.utf8) == Data(destination.target.materialID.utf8)',s);self.assertIn('pendingMaterials?.filter',s);self.assertIn('!controller.model.draft.chapters.flatMap',s)
 def test_pending_publisher_retires_async_and_staged_work(self):
  s=self.read('App/ProjectNodePlacePicker.swift');self.assertIn('pendingTarget?.controller.objectWillChange.sink { [weak self] _ in self?.retire() }',s);self.assertIn('value.snapshot.isCurrent(model: model)',s)
 def test_full_host_identity(self):
  s=self.read('App/ProjectPendingNodePlacePicker.swift');self.assertIn('owner: ObjectIdentifier(model), controller: ObjectIdentifier(pending)',s);self.assertIn('reader: reader.map(ObjectIdentifier.init), destination: destination.id',s)
 def test_existing_picker_and_reader_reused(self):
  s=self.read('App/ProjectPendingNodePlacePicker.swift');self.assertIn('ProjectNodePlacePickerHost(',s);self.assertIn('@Environment(\\.projectNodePlaceReader)',s);self.assertNotIn('URLSession',s);self.assertNotIn('cityNodes(',s)
 def test_only_edit_form_mount(self):
  s=self.read('App/ProjectEditPendingPresentation.swift');mount='ProjectPendingNodePlacePickerEntry(model: model, pending: controller, destination: original)';self.assertEqual(s.count(mount),1);self.assertLess(s.index('case .edit:'),s.index(mount));self.assertLess(s.index(mount),s.index('case .remove:'))
 def test_shared_mutation_and_noop_preservation(self):
  s=self.read('Core/ProjectNodePlaceSelection.swift');self.assertIn('Self.replacingLocation(of: draft.chapters[chapterIndex].nodes[nodeIndex], with: poi)',s);self.assertIn('if Double(next.latitude) != coordinate.latitude',s);self.assertIn('if next.name.isEmpty',s)
if __name__=='__main__':unittest.main()

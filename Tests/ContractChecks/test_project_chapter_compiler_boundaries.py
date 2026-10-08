"""Source-only regression checks; SwiftUI compilation and accessibility runtime require Apple CI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ProjectEditChapterCompilerBoundaries(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/ProjectEditView.swift').read_text()
        self.body = self.source.split('    var body: some View {', 1)[1].split('    private func chapterStructure(', 1)[0]
        self.structure = self.source.split('    private func chapterStructure(', 1)[1].split('    private func chapterLabel(', 1)[0]
        self.label = self.source.split('    private func chapterLabel(', 1)[1].split('    private var basicFields:', 1)[0]

    def test_section_and_label_have_separate_typed_expression_boundaries(self):
        self.assertIn('@MainActor struct ProjectEditView: View', self.source)
        self.assertIn('chapterStructure(opening: opening)', self.body)
        self.assertNotIn('ForEach(model.draft.chapters)', self.body)
        self.assertIn('opening: ProjectEditStarterController.Lease?) -> some View', self.structure)
        self.assertIn('chapterLabel(chapter)', self.structure)
        self.assertIn('_ chapter: ProjectEditChapter) -> some View', self.label)
        self.assertNotIn('AnyView', self.structure + self.label)

    def test_label_keeps_literal_count_and_localized_accessibility_title(self):
        for token in ['let nodeCount = chapter.nodes.count',
                      r'let nodeCountLabel: Text = Text("projectEdit.nodeCount") + Text(verbatim: ": \(nodeCount)")',
                      'ProjectEditName(value: chapter.name, fallback: "projectEdit.untitledChapter")',
                      'Text(verbatim: String(nodeCount)).font(.caption).foregroundStyle(.secondary)',
                      '.accessibilityLabel(nodeCountLabel)', 'VStack(alignment: .leading, spacing: 4)']:
            self.assertIn(token, self.label)
        self.assertNotIn('String(localized:', self.label)
        self.assertNotIn('Locale(', self.label)

    def test_structure_keeps_captured_lease_guards_routes_and_environment_locale(self):
        self.assertIn('let opening = model.captureStarterLease()', self.body)
        self.assertNotIn('captureStarterLease()', self.structure)
        for token in ['Section("projectEdit.structure")', 'ForEach(model.draft.chapters)',
                      'ProjectEditChapterView(model: model, chapterID: chapter.id)',
                      '.accessibilityIdentifier("projectEdit.chapter." + chapter.id)',
                      '.onDelete { chapterRemoval.open(offsets: $0, captured: removalCapture) }',
                      'let removalCapture = chapterRemoval.capture()', '.deleteDisabled(removalCapture == nil)',
                      '.onMove { if model.fullEdit { model.draft.chapters.move(fromOffsets: $0, toOffset: $1) } }',
                      'model.draft.chapters.filter { $0.preserved["opening"] != .bool(true) }.count + 1',
                      r'LocalizedStringResource("projectStarter.defaultChapter", defaultValue: "Chapter \(ordinal)", locale: locale)',
                      'starter.createChapter(lease: opening, name: name)',
                      '.disabled(!model.fullEdit).accessibilityIdentifier("projectEdit.addChapter")']:
            self.assertIn(token, self.structure)
        host = (ROOT / 'App/ProjectChapterRemovalPresentation.swift').read_text()
        model = (ROOT / 'App/ProjectEditStarterController.swift').read_text()
        self.assertIn('guard fullEdit, let session = coordinator.session', model)
        for guard in ['model.isCurrentStarterLease(value.lease)',
                      'model.draftMutationRevision == value.revision',
                      'ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes',
                      'guard !saving, !saveUnconfirmed, isCurrent(value)',
                      'model.coordinator.suspendLocalWritesAfterChapterRemoval(value.readback)']:
            self.assertIn(guard, host)
        self.assertIn('ownsVisit && !coordinator.hasUnconfirmedChapterRemoval', self.source)
        # These negative checks deliberately reject a regression to direct removal,
        # a new unconfirmed deletion path, or a raw store/remote-submit bypass.
        for forbidden in ['chapters.remove(', 'chapters.removeAll', 'persistLocalChange(',
                          'coordinator.confirm(', 'store.save(']:
            self.assertNotIn(forbidden, self.structure)
        for forbidden in ['StateObject', '@State ', '.onAppear', '.task', 'AnyView']:
            self.assertNotIn(forbidden, self.structure + self.label)

if __name__ == '__main__': unittest.main()

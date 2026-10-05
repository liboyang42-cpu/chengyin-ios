"""Stable native metadata sheet host; runtime presentation remains an Apple gate."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MetadataPresentationHostChecks(unittest.TestCase):
    def test_concrete_host_wraps_lazy_rows_and_owns_exactly_one_sheet(self):
        source = (ROOT / 'App/TemplateAuthoringMetadataSelectors.swift').read_text()
        host = source.split('@MainActor struct TemplateAuthoringMetadataFields: View {')[1].split('@MainActor private struct TemplateAuthoringMetadataSelector')[0]
        self.assertIn('VStack(spacing: 12) {\n            ForEach(TemplateMetadataField.allCases)', host)
        self.assertEqual(host.count('.sheet(item: $presented)'), 1)
        self.assertIn('.buttonStyle(.borderless)', host)
        self.assertIn('.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())', host)
        self.assertIn('Button { presented = field }', host)
        self.assertIn('field: field)', host)

    def test_real_open_checks_selected_destination_and_retains_lifecycle_fences(self):
        tests = (ROOT / 'Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift').read_text()
        self.assertIn('tap("templateMetadata.open." + field', tests)
        self.assertIn('app.buttons["templateMetadata.cancel"].waitForExistence', tests)
        self.assertIn('app.navigationBars[title].waitForExistence', tests)
        source = (ROOT / 'App/TemplateAuthoringMetadataSelectors.swift').read_text()
        for token in ['originalDraft == model.draft', 'modelGeneration == model.metadataGeneration',
                      'readerIdentity == reader?.discoveryPresentationIdentity',
                      '.onDisappear { editor.close() }', 'generation += 1',
                      'guard accepts(stamp) else { return }']:
            self.assertIn(token, source)


if __name__ == '__main__': unittest.main()

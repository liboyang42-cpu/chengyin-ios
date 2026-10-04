"""Run51 retained-image/shelf source checks only; not runtime evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(name): return (ROOT/name).read_text()

class RetainedShelfUIRegressions(unittest.TestCase):
    def test_fixture_selection_and_consumer_keep_one_context_identity(self):
        text = read('App/RetainedImageFixtureView.swift')
        self.assertTrue(text.startswith('#if DEBUG'))
        self.assertIn('@State private var context: RetainedImageSelectionContext', text)
        self.assertIn('_context = State(initialValue:', text)
        self.assertIn('context.uploads.prepare(sanitized, scope: context.scope)', text)
        self.assertIn('RetainedImageSelectionView(context: context)', text)
        self.assertIn('picker: .init(present: { _ in false }, dismiss: {})', text)
        self.assertNotIn('URLSession', text.replace('// No URLSession/socket.', ''))

    def test_row_actions_remain_independent_and_fail_closed(self):
        text = read('App/RetainedImageSelectionView.swift')
        self.assertIn('.buttonStyle(.borderless)', text)
        for expected in ['!model.context.picker.enabled', 'model.context.uploads.locked',
                         'await model.context.uploads.confirm(review)',
                         'model.context.uploads.applyLocally(image, consume: apply)',
                         '.onDisappear { model.leave() }']:
            self.assertIn(expected, text)
        tests = read('Tests/AppUITests/RetainedImageUITests.swift')
        self.assertIn('XCTAssertFalse(app.buttons["image.retained.select"].isEnabled)', tests)
        self.assertIn('func testUnknownUploadCannotBeRetried()', tests)
        self.assertIn('XCTAssertFalse(app.buttons["image.retained.confirmUpload"].exists)', tests)

    def test_shelf_identity_and_terminal_outcomes_are_exact(self):
        view = read('App/TemplateAuthoringMineView.swift')
        self.assertIn('.accessibilityValue(Text(verbatim: String(value.templateID.rawValue)))', view)
        self.assertIn('.disabled(locked || busy || !coordinator.rows.contains(row))', view)
        self.assertIn('coordinator.cancelShelfReview()', view)
        tests = read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift')
        for expected in ['XCTAssertEqual(identity.value as? String, "901")',
                         'XCTAssertEqual(status.label, "Simulation completed. No template was saved to a server or published.")',
                         'XCTAssertFalse(button.isEnabled)',
                         'XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].isEnabled)',
                         'XCTAssertEqual(cancel.label, "取消"); cancel.tap()']:
            self.assertIn(expected, tests)
        self.assertNotIn('app(["-AppleLanguages"', tests)

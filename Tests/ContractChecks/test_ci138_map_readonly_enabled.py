"""CI138 UI68 candidate: preserve native disabled state on the complete AX row.

These exact source checks do not establish native AX behavior. Run the original
UI68 journey on Apple; never substitute a weaker enabled-state assertion.
"""
from pathlib import Path
import hashlib
import unittest
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BEFORE = '2fca852999967960bd6a5a7b53ed8eb3c4c453227ec3c1e5be51c78bcf517af6'
AFTER = 'cd0c1f30ec9c42278335f79fe0786e379c15f4b1cb26cc7db2b9fa20bdc25283'
UI_SHA = '57f1c4b1e01ec0bed5313181ceaf8583c2cdbdf57f30d1c74973550d9ddaa9da'
DISABLED = '                        .disabled(onSelect == nil)\n'
ROLE = '                        .accessibilityAddTraits(.isButton)\n'
HEAD = '                    }.buttonStyle(.plain)\n                        .accessibilityElement(children: .ignore)\n'
TAIL = '                        .accessibilityIdentifier("mapList.pin.\\(pin.id)")\n'


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def original_source(source):
    if digest(source) != AFTER or source.count(DISABLED) != 1:
        raise ValueError('Unreviewed alternative-list source')
    if source.count(TAIL + DISABLED) != 1 or source.count(HEAD) != 1:
        raise ValueError('Disabled must wrap the entire custom accessibility row')
    previous = source.replace(TAIL + DISABLED, TAIL, 1).replace(
        HEAD, HEAD.replace('                        .accessibilityElement', DISABLED + '                        .accessibilityElement'), 1)
    if digest(previous) != BEFORE:
        raise ValueError('The complete original map source was not restored')
    return previous


def verify(source, tests):
    original_source(source)
    if digest(tests) != UI_SHA:
        raise ValueError('Original UI68 journeys, assertions and waits must remain exact')
    for required in (
        'guard isExpanded, renderedInput == currentInput, let request,',
        'let id = gate.consume(request) else { return }',
        'onSelect?(id)',
        '.accessibilityElement(children: .ignore)',
        '.accessibilityLabel(Text(verbatim: pin.title))',
        '.accessibilityValue(pin.id == selectedID ? Text("mapList.selected") : Text(""))',
        '.accessibilityHint(onSelect == nil ? Text("mapList.readOnly") : pinHint(pin.id))',
        ROLE,
        '.accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])',
        'selectionEnabled: onSelect != nil',
    ):
        if required not in source:
            raise ValueError('Existing selection, lifecycle or accessibility semantics changed')


def read_sources(root):
    root = Path(root)
    from tools.run138_current_source_projection import original_feature_batch_bytes
    relative = 'App/QuestifyDensityMap.swift'
    view = original_feature_batch_bytes(relative, (root / relative).read_bytes())
    return (view.decode('utf-8'),
            (root / 'Tests/AppUITests/SearchMapAlternativeListFlowTests.swift').read_bytes().decode('utf-8'))


class MapReadOnlyEnabledContracts(unittest.TestCase):
    def sources(self):
        return read_sources(ROOT)

    def test_on_disk_crlf_is_not_normalized_before_admission(self):
        paths = ('App/QuestifyDensityMap.swift', 'Tests/AppUITests/SearchMapAlternativeListFlowTests.swift')
        originals = [(ROOT / path).read_bytes() for path in paths]
        for changed_index in range(2):
            with self.subTest(path=paths[changed_index]), tempfile.TemporaryDirectory(prefix='map-byte-admission-') as directory:
                target = Path(directory)
                for index, path in enumerate(paths):
                    file = target / path
                    file.parent.mkdir(parents=True, exist_ok=True)
                    raw = originals[index]
                    file.write_bytes(raw.replace(b'\n', b'\r\n') if index == changed_index else raw)
                with self.assertRaises(ValueError):
                    verify(*read_sources(target))

    def test_only_disabled_modifier_order_changes(self):
        source, tests = self.sources()
        verify(source, tests)
        self.assertEqual(digest(original_source(source)), BEFORE)

    def test_original_complete_readonly_and_return_journey_is_unchanged(self):
        source, tests = self.sources()
        verify(source, tests)
        self.assertEqual(tests.count('    func test'), 3)
        self.assertIn('XCTAssertFalse(app.buttons["mapList.pin.list-first"].isEnabled)', tests)
        self.assertIn('XCTAssertFalse(app.buttons["mapList.pin.list-second"].isEnabled)', tests)
        self.assertIn('maximumSwipes: 20', tests)

    def test_mutations_to_disabled_role_selection_label_or_gates_fail_closed(self):
        source, tests = self.sources()
        for before, after in (
            (DISABLED, ''), (DISABLED, DISABLED + DISABLED),
            ('.disabled(onSelect == nil)', '.disabled(false)'),
            (ROLE, ''), (ROLE, ROLE.replace('.isButton', '.isStaticText')),
            ('.isSelected : []', '[] : []'),
            ('Text(verbatim: pin.title)', 'Text("Short title")'),
            ('onSelect?(id)', 'onSelect!(id)'),
            ('let id = gate.consume(request)', 'let id = Optional(request.id)'),
            ('renderedInput == currentInput', 'true'),
        ):
            self.assertIn(before, source)
            with self.subTest(before=before), self.assertRaises(ValueError):
                verify(source.replace(before, after, 1), tests)
        for changed in [source + '\n', source.replace('\n', '\r\n'), original_source(source)]:
            with self.assertRaises(ValueError):
                verify(changed, tests)

    def test_test_locator_assertions_and_wait_caps_cannot_be_relaxed(self):
        source, tests = self.sources()
        for before, after in [('app.buttons[id]', 'app.otherElements[id]'),
                              ('timeout: 5', 'timeout: 20'),
                              ('XCTAssertFalse(app.buttons["mapList.pin.list-first"].isEnabled)', 'XCTAssertTrue(true)')]:
            self.assertIn(before, tests)
            with self.subTest(before=before), self.assertRaises(ValueError):
                verify(source, tests.replace(before, after, 1))


if __name__ == '__main__':
    unittest.main()

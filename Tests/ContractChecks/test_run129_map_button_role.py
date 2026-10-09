"""Run129 UI65 exact AX-role repair; no locator fallback or business-authority change."""
from pathlib import Path
import hashlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
BEFORE='3bf994ff339d52b23db079bd662cb81043fd4583256937b44f0cb77708f8833d'
AFTER='2fca852999967960bd6a5a7b53ed8eb3c4c453227ec3c1e5be51c78bcf517af6'
UI='57f1c4b1e01ec0bed5313181ceaf8583c2cdbdf57f30d1c74973550d9ddaa9da'
INSERT='                        .accessibilityAddTraits(.isButton)\n'
def verify(view,tests):
    assert hashlib.sha256(view.encode()).hexdigest()==AFTER, 'Unreviewed map source change'
    assert view.count(INSERT)==1
    assert hashlib.sha256(view.replace(INSERT,'',1).encode()).hexdigest()==BEFORE, 'More than the single role was changed'
    assert hashlib.sha256(tests.encode()).hexdigest()==UI, 'The original complete UI journeys must stay exact'
    assert 'let button = app.buttons[id]' in tests
    assert '.accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])' in view
    assert '.disabled(onSelect == nil)' in view
    assert '.accessibilityLabel(Text(verbatim: pin.title))' in view
    assert '.accessibilityIdentifier("mapList.pin.\\(pin.id)")' in view
class Run129MapButtonRole(unittest.TestCase):
    def sources(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('map_readonly_inverse', ROOT / 'tools/map_readonly_inverse.py')
        inverse = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(inverse)
        relative = 'App/QuestifyDensityMap.swift'
        view = inverse.original_source(relative, (ROOT / relative).read_bytes(), ROOT).decode('utf-8')
        tests = (ROOT / 'Tests/AppUITests/SearchMapAlternativeListFlowTests.swift').read_bytes().decode('utf-8')
        return view, tests
    def test_only_explicit_button_role_added_to_the_original_control(self):verify(*self.sources())
    def test_button_selected_disabled_and_label_cannot_be_dropped_or_replaced(self):
        view,tests=self.sources()
        for old,new in [(INSERT,''),('.accessibilityAddTraits(.isButton)','.accessibilityAddTraits(.isStaticText)'),('.disabled(onSelect == nil)','.disabled(false)'),('.isSelected : []','[] : []'),('Text(verbatim: pin.title)','Text("Short title")')]:
            self.assertIn(old,view)
            with self.subTest(old=old),self.assertRaises(AssertionError):verify(view.replace(old,new,1),tests)
    def test_other_element_locator_or_weaker_readiness_is_rejected(self):
        view,tests=self.sources()
        for old,new in [('app.buttons[id]','app.otherElements[id]'),('timeout: 5','timeout: 8'),('XCTAssertFalse(first.isSelected)','XCTAssertTrue(true)')]:
            self.assertIn(old,tests)
            with self.subTest(old=old),self.assertRaises(AssertionError):verify(view,tests.replace(old,new,1))
    def test_all_three_complete_cases_and_maximum_type_remain(self):
        _,tests=self.sources();self.assertEqual(tests.count('    func test'),3)
        self.assertIn('for chinese in [false, true]',tests)
        self.assertIn('dynamicTypeSize: "accessibility5"',tests)
        self.assertIn('maximumSwipes: 20',tests)
        self.assertIn('XCTAssertFalse',tests)

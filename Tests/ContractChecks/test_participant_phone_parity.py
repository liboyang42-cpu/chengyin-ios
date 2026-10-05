"""Native source wiring checks, not Swift execution or external-source verification."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ParticipantPhoneParityTests(unittest.TestCase):
    def test_validation_checks_length_before_second_ascii_digit(self):
        source = (ROOT / 'Core/ParticipantForm.swift').read_text()
        self.assertIn('bytes.count != 11 || bytes.first != 49 || !(51...57).contains(bytes[1])', source)
        self.assertIn('!bytes.allSatisfy({ (48...57).contains($0) })', source)
        self.assertIn('guard validation == nil', source)

    def test_form_and_both_dispatch_boundaries_use_validation(self):
        form = (ROOT / 'App/ParticipantFormView.swift').read_text()
        self.assertIn('canMutate && draft.validation == nil', form)
        self.assertIn('try mutation.fields()', (ROOT / 'Core/ParticipantCoordinator.swift').read_text())
        self.assertIn('try mutation.fields()', (ROOT / 'Core/ParticipantService.swift').read_text())

    def test_hint_matches_localization_source(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']['participant.form.phoneHint']['localizations']
        source = next(x for x in json.loads((ROOT / 'docs/participant-localizations.json').read_text()) if x['key'] == 'participant.form.phoneHint')
        for language in ['en', 'zh-Hans']:
            self.assertEqual(catalog[language]['stringUnit']['value'], source[language])
        self.assertIn('13', source['en'])
        self.assertIn('19', source['zh-Hans'])

    def test_regression_vectors_cover_create_edit_and_no_write(self):
        for filename in ['ParticipantServiceTests.swift', 'ParticipantCoordinatorTests.swift']:
            source = (ROOT / 'Tests/CoreTests' / filename).read_text()
            for value in ['10000000000', '11000000000', '12000000000']:
                self.assertIn(value, source)
            self.assertIn('ParticipantFormDraft(detail: try participantFixture())', source)
        self.assertIn('for prefix in 3...9', (ROOT / 'Tests/CoreTests/ParticipantFormTests.swift').read_text())

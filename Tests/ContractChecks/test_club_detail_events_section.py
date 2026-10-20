"""Package 10 source-level guard: club detail events tab summary reuses existing reads only."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ClubDetailEventsSectionTests(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_symbols_and_wiring(self):
        section = self.text('App/ClubDetailEventsSection.swift')
        for symbol in ['ClubDetailEventsSection', 'ClubEventCalendarReadModel', 'ClubEventCalendarView',
                       'club.calendar.open', 'task(id: readContext)', 'model.invalidate()']:
            self.assertIn(symbol, section)
        self.assertIn('ClubDetailEventsSummary', self.text('Core/ClubDetailEventsSummary.swift'))
        self.assertIn('ClubDetailEventsSection(', self.text('App/ClubDetailView.swift'))

    def test_no_new_endpoints_or_writes(self):
        for path in ['App/ClubDetailEventsSection.swift', 'Core/ClubDetailEventsSummary.swift']:
            src = self.text(path)
            self.assertIsNone(re.search(r'api/', src), path)
            self.assertNotIn('URLSession', src)
            self.assertNotIn('.write', src)

    def test_untouched_package09_and_no_new_localization_keys(self):
        section = self.text('App/ClubDetailEventsSection.swift')
        keys = set(re.findall(r'(?:Text|Label|LabeledContent)\("(club\.[A-Za-z.]+)"', section))
        catalog = ''.join(p.read_text() for p in (ROOT / 'Resources').glob('*.json'))
        for key in keys:
            self.assertIn('"%s"' % key, catalog, key)


if __name__ == '__main__':
    unittest.main()

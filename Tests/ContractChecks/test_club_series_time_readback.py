"""Source-only safety checks; does not execute Swift or certify native UI."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class ClubSeriesTimeReadbackChecks(unittest.TestCase):
    def test_update_requires_valid_readback(self):
        source = (ROOT / 'Core/ClubGovernanceFormDraft.swift').read_text()
        self.assertIn('operation == .createSeries ? "09:00" : ""', source)
        self.assertIn('if let time = seed["startTime"]?.string, ClubSeriesScheduleDraft.parseTime(time) != nil', source)
        self.assertIn('text["startTime"] = time', source)
    def test_unknown_editor_never_presents_default_picker(self):
        source = (ROOT / 'App/ClubSeriesScheduleEditor.swift').read_text()
        self.assertIn('if ClubSeriesScheduleDraft.parseTime(schedule.startTime) == nil', source)
        self.assertIn('TextField("HH:mm", text: $schedule.startTime)', source)
        self.assertIn('club.schedule.startTime.unknown', source)
        self.assertIn('schedule = session.initial', source)
        self.assertIn('schedule.issue(now: clock.date) != nil', source)
    def test_no_update_fallback_and_native_regressions(self):
        source = (ROOT / 'Core/ClubSeriesScheduleDraft.swift').read_text()
        self.assertIn('form.operation == .createSeries ? "09:00" : ""', source)
        self.assertIn('guard Self.parseTime(startTime) != nil else { return .time }', source)
        tests = (ROOT / 'Tests/CoreTests/ClubSeriesScheduleDraftTests.swift').read_text()
        for name in ['testUnknownUpdateTimeRequiresExplicitChoiceIncludingNineAM',
                     'testMissingReadbackAndMissingDraftTimeNeverUseCreateDefault',
                     'testAppendDatePreservesMidnightBoundaryTimeAndUpdateContract',
                     'testSwitchingToUnknownSeriesDoesNotReusePreviousTimeAndResetRestoresUnknown']:
            self.assertIn('func ' + name, tests)

if __name__ == '__main__':
    unittest.main()

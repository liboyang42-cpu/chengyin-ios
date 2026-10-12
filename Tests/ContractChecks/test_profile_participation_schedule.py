"""Source contracts for local display only; no Swift runtime/production read evidence."""
import json,re,unittest
from pathlib import Path
W=Path(__file__).resolve().parents[2]
C=(W/'Core/ProfileParticipationSchedule.swift').read_text();A=(W/'App/ProfileParticipationScheduleSection.swift').read_text();V=(W/'App/PlayerJourneyViews.swift').read_text()
class ProfileParticipationScheduleSourceTests(unittest.TestCase):
 def test_01_existing_parser(self):self.assertIn('OrderLifecycleTime.date(rawStart)',C);self.assertIn('OrderLifecycleTime.date(rawEnd)',C)
 def test_02_shanghai_dates(self):self.assertEqual(C.count('TimeZone(identifier: "Asia/Shanghai")'),2)
 def test_03_before_start(self):self.assertIn('now < start, now <= end',C)
 def test_04_calendar_days(self):self.assertIn('calendar.startOfDay(for: now)',C);self.assertIn('calendar.startOfDay(for: start)',C);self.assertIn('calendar.dateComponents([.day], from: today, to: startDay).day',C)
 def test_05_one_to_three(self):self.assertIn('(1...3).contains($0) ? $0 : nil',C)
 def test_06_reversed_unknown(self):self.assertIn('end >= start else',C);self.assertIn('self.start = nil; self.end = nil; range = nil',C)
 def test_07_invalid_clock(self):self.assertIn('now.timeIntervalSince1970.isFinite',C)
 def test_08_invalid_source(self):self.assertIn('start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite',C)
 def test_09_range_calendar(self):self.assertIn('formatter.calendar = Calendar(identifier: .gregorian)',C);self.assertIn('formatter.dateFormat = "yyyy.MM.dd"',C)
 def test_10_range_when_not_near(self):self.assertIn('return .init(range: range, reminderDays: nil)',C)
 def test_11_no_elapsed_day_rounding(self):self.assertNotIn('86400',C);self.assertNotIn('ceil(',C);self.assertNotIn('TimeZone.current',C)
 def test_12_actual_detail_mount(self):self.assertIn('ProfileParticipationScheduleSection(start: detail.record.order.ownerStartDate,\n                    end: detail.record.order.ownerEndDate)',V)
 def test_13_local_timer(self):self.assertIn('TimelineView(.periodic(from: Date(), by: 1))',A);self.assertIn('schedule.presentation(now: clock.date)',A)
 def test_14_unknown_no_shell(self):self.assertIn('if let range = presentation.range {',A)
 def test_15_no_color_only_warning(self):self.assertIn('Label("profile.participationSchedule.soon", systemImage:',A);self.assertIn('LabeledContent("profile.participationSchedule.days")',A)
 def test_16_clock_basis(self):self.assertIn('profile.participationSchedule.clockNote',A)
 def test_17_no_extra_reads(self):
  for text in ['URLSession','HTTPTransport','token:','UserDefaults','UNUserNotificationCenter','EventKit','readsEnabled = true','cancelParticipation','canCancel(','.refund']:self.assertNotIn(text,C+A)
 def test_18_gate_stays_off(self):
  s=(W/'Core/PlayerJourneyService.swift').read_text();self.assertIn('readsEnabled: Bool = false',s);self.assertIn('guard readsEnabled else { throw APIError.notConfigured }',s)
 def test_19_normal_factory_stays_off(self):
  s=(W/'App/AppSession.swift').read_text();self.assertIn('PlayerJourneyService(configuration: $0, transport: runtimeHTTPTransport)',s)
 def test_20_owner_approval_unchanged_boundary(self):self.assertIn('until the backend null-principal guard is independently accepted and deployed',(W/'Core/OwnedOrderRead.swift').read_text())
 def test_21_native_inventory(self):
  for path,count in [('CoreTests/ProfileParticipationScheduleTests.swift',16),('AppUnitTests/ProfileParticipationScheduleAppTests.swift',6),('AppUITests/ProfileParticipationScheduleFlowTests.swift',6)]:self.assertEqual(len(re.findall(r'func test\w+\(', (W/'Tests'/path).read_text())),count)
 def test_22_bilingual(self):
  f=json.loads((W/'Resources/ProfileParticipationScheduleLocalizations.fragment.json').read_text())['strings'];self.assertEqual(len(f),4)
  for v in f.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()

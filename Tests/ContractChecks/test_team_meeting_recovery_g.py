#!/usr/bin/env python3
"""Source locks and a decision table for team-meeting recovery. Does not execute Swift."""
import base64, pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

def between(text, start, end):
    i = text.index(start)
    return text[i:text.index(end, i)]

class Intent:
    def __init__(self):
        self.rows = {}
        self.sends = 0
        self.lookups = 0
    def record(self, owner, team, meeting):
        return self.rows.get((owner, team, meeting))
    def claim(self, owner, team, meeting, request, decision):
        key = (owner, team, meeting)
        existing = self.rows.get(key)
        if existing is not None:
            first = existing["phase"] == "prepared" and existing["request"] == request
            replacement = existing["phase"] == "refused" and existing["request"] != request
            if not first and not replacement:
                return existing["phase"], False
        self.rows[key] = {"request": request, "phase": "prepared"}
        self.rows[key]["phase"] = "unknown"
        self.sends += 1
        if decision is None:
            return "unknown", True
        phase = "confirmed" if decision else "refused"
        self.rows[key]["phase"] = phase
        return phase, True
    def lookup(self, owner, team, meeting, decision):
        self.lookups += 1
        row = self.rows.get((owner, team, meeting))
        if row is None:
            return None
        if row["phase"] in ("confirmed", "refused", "cancelledBeforeSend"):
            return row["phase"]
        if decision is None:
            return row["phase"]
        row["phase"] = "confirmed" if decision else "refused"
        return row["phase"]
    def classify(self, owner, team, meeting):
        row = self.rows.get((owner, team, meeting))
        if row is None or row["phase"] in ("prepared", "cancelledBeforeSend", "refused"):
            if row is not None and row["phase"] == "prepared":
                row["phase"] = "cancelledBeforeSend"
            return "notSent"
        if row["phase"] == "unknown":
            return "sentUnknown"
        return "confirmed"

class TeamMeetingRecoveryContract(unittest.TestCase):
    def text(self, name):
        return (ROOT / name).read_text()
    def test_wire_keeps_the_old_confirm_body_and_stores_no_secret(self):
        journal = self.text("Core/TeamMeetingPendingJournal.swift")
        recovery = self.text("Core/TeamMeetingRecovery.swift")
        meeting = self.text("Core/TeamFirstMeeting.swift")
        encode = between(journal, "func encode", "func decode")
        self.assertIn('["schema", "ownerID", "namespace", "teamId", "meetingId", "requestId", "phase"]', journal)
        for banned in ("nonce", "signature", "token", "keyVersion"):
            self.assertNotIn(banned, encode)
        self.assertIn("as? NSNumber", journal)
        self.assertIn('.replacingOccurrences(of: "=", with: "")', journal)
        self.assertNotIn("URLSession", journal + recovery)
        pattern = re.compile(r"\A[A-Za-z0-9_-]{1,1024}\Z")
        for sample in ((901, "offline-team-fixture", "4101", "meet-4101"), (1, "a", "b0", "c")):
            raw = f"{sample[0]}\n{sample[1]}\n{sample[2]}\n{sample[3]}".encode()
            key = base64.b64encode(raw).decode().replace("/", "_").replace("+", "-").replace("=", "")
            self.assertRegex(key, pattern)
            self.assertNotIn("=", key)
        self.assertIn('return ["meetingId": challenge.meetingId, "teamId": challenge.teamId, "nonce": challenge.nonce', meeting)
        claim = between(recovery, "func claimAndSend", "func lookup")
        self.assertLess(claim.index("markUnknown"), claim.index("service.confirm(fields)"))
        lookup = between(recovery, "func lookup", "func classifyCancel")
        self.assertNotIn("service.confirm(", lookup)
        self.assertIn("confirmationReadback", lookup)
        classify = between(recovery, "func classifyCancel", "private static func make")
        self.assertNotIn("service.confirm(", classify)
        self.assertNotIn("service.cancel(", classify)
        self.assertIn("case .unknown:", classify)
        self.assertIn("return .sentUnknown", classify)
        self.assertIn("return .confirmed", classify)
    def test_button_looks_up_and_home_refreshes(self):
        views = self.text("App/TeamReformFlowViews.swift")
        home = self.text("App/TeamHomeView.swift")
        flow = self.text("Core/TeamMeetingFlow.swift")
        entries = between(views, "struct TeamReformEntries", "struct TeamReformSheetHost")
        self.assertIn("teamReform.meeting.recovery", entries)
        self.assertIn("查原会面请求", entries)
        self.assertNotIn("submitScanned", entries)
        handshake = between(views, "private var handshake", "private func scanIssueKey")
        self.assertLess(handshake.index("blocksResend"), handshake.index("simulateScan"))
        self.assertIn("确认已发出但结果未知，不能重发。请查原请求。", views)
        self.assertIn("确认尚未发送，已在本地取消。", views)
        self.assertIn("会面已确认，取消不会再次确认。", views)
        self.assertIn("onDismiss:", home)
        self.assertIn("await reload(permit: permit)", home)
        self.assertIn("journal: TeamMeetingPendingJournal? = nil", flow)
        close = between(flow, "func close()", "private func recovery()")
        self.assertNotIn("removeItem", close)
        submit = between(flow, "func submitScanned", "func readBackConfirmation")
        self.assertLess(submit.index("journal == nil"), submit.index("service.confirm(fields)"))
        durable = between(flow, "func submitDurable", "func readBackDurable")
        self.assertLess(durable.index("blocksNewSend"), durable.index("value.scanned"))
        readback = between(flow, "func readBackDurable", "func cancelDurable")
        self.assertIn(".lookup(", readback)
        self.assertNotIn(".confirm(", readback)
        cancel = between(flow, "switch kind", "private func serverCancel")
        confirmed = cancel.split("case .sentUnknown")[0]
        self.assertIn("case .confirmed", confirmed)
        self.assertNotIn("serverCancel", confirmed)
        self.assertNotIn("value.cancel", confirmed)
    def test_decision_table_matches_the_adapter_rules(self):
        # Python mirror of the adapter branches. Not the Swift runtime.
        book = Intent()
        phase, sent = book.claim(901, "4101", "meet-4101", "request-0001", True)
        self.assertEqual((phase, sent, book.sends), ("confirmed", True, 1))
        phase, sent = book.claim(901, "4101", "meet-4101", "request-0001", True)
        self.assertEqual((phase, sent, book.sends), ("confirmed", False, 1))
        lost = Intent()
        phase, sent = lost.claim(901, "4101", "meet-4101", "request-0001", None)
        self.assertEqual(phase, "unknown")
        phase, sent = lost.claim(901, "4101", "meet-4101", "request-0002", True)
        self.assertFalse(sent)
        self.assertEqual(lost.sends, 1)
        self.assertEqual(lost.lookup(901, "4101", "meet-4101", None), "unknown")
        self.assertEqual(lost.lookup(901, "4101", "meet-4101", True), "confirmed")
        self.assertEqual(lost.sends, 1)
        refused = Intent()
        refused.claim(901, "4101", "meet-4101", "request-0001", False)
        phase, sent = refused.claim(901, "4101", "meet-4101", "request-0001", True)
        self.assertFalse(sent)
        phase, sent = refused.claim(901, "4101", "meet-4101", "request-0002", True)
        self.assertEqual((phase, sent, refused.sends), ("confirmed", True, 2))
        prepared = Intent()
        prepared.rows[(901, "4101", "meet-4101")] = {"request": "request-0001", "phase": "prepared"}
        phase, sent = prepared.claim(901, "4101", "meet-4101", "request-0001", True)
        self.assertTrue(sent)
        self.assertEqual(prepared.sends, 1)
        self.assertEqual(prepared.classify(901, "4101", "meet-4101"), "confirmed")
        unsent = Intent()
        unsent.rows[(901, "4101", "meet-4101")] = {"request": "request-0001", "phase": "prepared"}
        self.assertEqual(unsent.classify(901, "4101", "meet-4101"), "notSent")
        self.assertEqual(unsent.record(901, "4101", "meet-4101")["phase"], "cancelledBeforeSend")
        self.assertEqual(unsent.sends, 0)
        phase, sent = unsent.claim(901, "4101", "meet-4101", "request-0002", True)
        self.assertFalse(sent)
        unknown = Intent()
        unknown.rows[(901, "4101", "meet-4101")] = {"request": "request-0001", "phase": "unknown"}
        self.assertEqual(unknown.classify(901, "4101", "meet-4101"), "sentUnknown")
        self.assertEqual(unknown.record(901, "4101", "meet-4101")["phase"], "unknown")
        self.assertIsNone(unknown.record(903, "4101", "meet-4101"))
        self.assertIsNone(unknown.record(901, "9999", "meet-9999"))

if __name__ == "__main__":
    unittest.main()

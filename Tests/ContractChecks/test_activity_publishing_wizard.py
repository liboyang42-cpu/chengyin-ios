"""Activity wizard step machine. Mirrors Core/ActivityPublishingWizard.swift.

Not a Swift compiler, XCTest, UI, or device run. The step table is the mini-program
grouping from hengyin chengyinhub-xcx/pages/publish/activity (index.js blob
062721fd2b9e5d9804191e76a10bea899d84cc94, index.wxml blob
020247df65efefc61b015b6dd392127a823d4c2b). Field acceptance is the existing
ActivityPublishDraft.wire predicate, split across those steps.
"""
import hashlib, re, unittest
from datetime import datetime
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STEPS = [
    ("basic", "基本信息", "这场活动叫什么、在哪儿办？", ["name", "addressName", "startDate", "endDate", "categoryIds"]),
    ("content", "活动内容", "这场活动玩什么？", ["description", "imgUrl", "templateId"]),
    ("ticket", "票务与合作", "这场活动怎么卖票？", ["ticket*"]),
]
QUICK_SHA = "dc44fc165361e3b3906bb6753f16558506e1407788ab5c84f9a6e86d8b82d142"
PREFIX_SHA = "ba5179bf5d05540f96b2c299a2ede1c591e5b1cf0cc7761ac27131a76f0e8e94"
SUFFIX_SHA = "2ca41887e8770bbea25ac45daf45dbab2c78a4b02bbda1779333fb7c9fa48d90"


def read(path):
    return (ROOT / path).read_text()


def filled(value):
    return value.strip() != ""


def date_time(value):
    text = value.strip().replace("T", " ")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        shape = text + " 00:00:00"
    elif re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", text):
        shape = text + ":00"
    elif re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", text):
        shape = text
    else:
        return None
    try:
        parsed = datetime.strptime(shape, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    return shape if parsed.strftime("%Y-%m-%d %H:%M:%S") == shape else None


def decimal_text(value):
    text = value.strip()
    if re.fullmatch(r"-?[0-9]+(?:\.[0-9]+)?", text) is None:
        return None
    return Decimal(text)


def stock_ok(value):
    if re.fullmatch(r"[+-]?\d+", value) is None:
        return False
    return int(value) > 0


def window(draft):
    start, end = date_time(draft["start"]), date_time(draft["end"])
    if start and end and end > start:
        return start, end
    return None


def ticket_ok(ticket, span):
    start, end = date_time(ticket["start"]), date_time(ticket["end"])
    price = decimal_text(ticket["price"])
    return (filled(ticket["name"]) and price is not None and price >= 0 and stock_ok(ticket["stock"])
            and start is not None and end is not None and end > start and start >= span[0] and end <= span[1])


def collaborators_ok(ids):
    return all(item > 0 for item in ids) and len(set(ids)) == len(ids)


def basic(draft):
    return window(draft) is not None and filled(draft["name"]) and filled(draft["addressName"]) and draft["categoryIDs"] and all(item > 0 for item in draft["categoryIDs"])


def content(draft):
    return filled(draft["description"]) and filled(draft["coverURL"]) and draft["templateID"] is not None


def tickets(draft):
    span = window(draft)
    return span is not None and collaborators_ok(draft["collaborators"]) and draft["tickets"] and all(ticket_ok(ticket, span) for ticket in draft["tickets"])


def complete(step, draft):
    return (basic, content, tickets)[clamp(step)](draft)


def clamp(step):
    return min(max(int(step), 0), len(STEPS) - 1)


def resolve(key):
    for index, step in enumerate(STEPS):
        for pattern in step[3]:
            if pattern.endswith("*"):
                prefix = pattern[:-1]
                if prefix and key.startswith(prefix):
                    return index
            elif pattern == key:
                return index
    return -1


def progress(current):
    active = clamp(current)
    return [{"key": step[0], "title": step[1], "index": index, "state": "done" if index < active else "current" if index == active else "todo"} for index, step in enumerate(STEPS)]


def resume(draft):
    for index in range(len(STEPS)):
        if not complete(index, draft):
            return index
    return len(STEPS) - 1


def advance(step, draft):
    current = clamp(step)
    if current + 1 < len(STEPS) and all(complete(index, draft) for index in range(current + 1)):
        return current + 1
    return None


def retreat(step):
    return max(clamp(step) - 1, 0)


def located(requested, draft):
    return min(clamp(requested), resume(draft))


def reason(step, draft):
    step = clamp(step)
    if step == 0:
        if not filled(draft["name"]):
            return "name"
        if not filled(draft["addressName"]):
            return "addressName"
        if date_time(draft["start"]) is None:
            return "startDate"
        if date_time(draft["end"]) is None:
            return "endDate"
        if window(draft) is None:
            return "endDate"
        if not draft["categoryIDs"] or any(item <= 0 for item in draft["categoryIDs"]):
            return "categoryIds"
        return None
    if step == 1:
        if not filled(draft["description"]):
            return "description"
        if draft["templateID"] is None:
            return "templateId"
        if not filled(draft["coverURL"]):
            return "imgUrl"
        return None
    if not collaborators_ok(draft["collaborators"]):
        return "collaborators"
    if not draft["tickets"]:
        return "ticket"
    span = window(draft)
    if span is None:
        return "startDate"
    for index, ticket in enumerate(draft["tickets"]):
        if not filled(ticket["name"]):
            return f"ticketName{index}"
        if decimal_text(ticket["price"]) is None or decimal_text(ticket["price"]) < 0:
            return f"ticketPrice{index}"
        if not stock_ok(ticket["stock"]):
            return f"ticketStock{index}"
        if date_time(ticket["start"]) is None:
            return f"ticketStart{index}"
        if date_time(ticket["end"]) is None:
            return f"ticketEnd{index}"
        if not ticket_ok(ticket, span):
            return f"ticketEnd{index}"
    return None


def blocking(step, draft):
    if complete(step, draft):
        return None
    return reason(step, draft) or "ticket"


def wire_accepts(draft):
    """Joined predicate from ActivityPublishDraft.wire(), not the step split."""
    span = window(draft)
    if not (filled(draft["name"]) and filled(draft["description"]) and filled(draft["addressName"])
            and filled(draft["coverURL"]) and span is not None and draft["templateID"] is not None
            and draft["categoryIDs"] and all(item > 0 for item in draft["categoryIDs"])
            and collaborators_ok(draft["collaborators"]) and draft["tickets"]):
        return False
    return all(ticket_ok(ticket, span) for ticket in draft["tickets"])


def blank():
    return {"name": "", "description": "", "coverURL": "", "addressName": "", "start": "", "end": "",
            "templateID": None, "categoryIDs": [], "collaborators": [], "tickets": []}


def ticket(**extra):
    value = {"name": "普通票", "price": "0", "stock": "10", "start": "2030-01-01 09:00:00", "end": "2030-01-01 18:00:00"}
    value.update(extra)
    return value


def ready():
    draft = blank()
    draft.update(name="城墙夜巡", description="沿城墙走一圈", coverURL="fixture://cover", addressName="西安城墙",
                 start="2030-01-01 09:00", end="2030-01-01T18:00:00", templateID=41, categoryIDs=[3, 8],
                 collaborators=[71, 72], tickets=[ticket(), ticket(name="夜场", price="12.50", stock="007")])
    return draft


class ActivityPublishingWizardContract(unittest.TestCase):
    def test_swift_step_table_matches_mini_program(self):
        source = read("Core/ActivityPublishingWizard.swift")
        found = re.findall(r'Step\(index: (\d+), key: "([^"]+)", title: "([^"]+)", heading: "([^"]+)", fields: \[([^\]]*)\]\)', source)
        self.assertEqual(len(found), 3)
        for index, (raw_index, key, title, heading, fields) in enumerate(found):
            expected = STEPS[index]
            parsed = re.findall(r'"([^"]*)"', fields)
            self.assertEqual((int(raw_index), key, title, heading, parsed), (index, *expected))
        for token in ["ProjectEditValidation.dateTime", "draft.categoryIDs.allSatisfy { $0 > 0 }",
                      "Set(draft.collaboratorMemberIDs).count == draft.collaboratorMemberIDs.count",
                      "$0.wire(activityStart:", "(try? draft.wire()) != nil",
                      'state: index < active ? "done" : index == active ? "current" : "todo"',
                      "return -1"]:
            self.assertIn(token, source)
        for forbidden in ["api/activity/publish", "mutationsConfigured", "prepareActivity", "transport.send"]:
            self.assertNotIn(forbidden, source)

    def test_untouched_publishing_slices_and_activity_handoff(self):
        text = read("App/PublishingModesViews.swift")
        quick = text.index("@MainActor struct QuickPublishingView")
        activity = text.index("@MainActor struct ActivityPublishingView")
        suffix = text.index("/// A local action lease")
        self.assertEqual(hashlib.sha256(text[quick:activity].encode()).hexdigest(), QUICK_SHA)
        self.assertEqual(hashlib.sha256(text[:quick].encode()).hexdigest(), PREFIX_SHA)
        self.assertEqual(hashlib.sha256(text[suffix:].encode()).hexdigest(), SUFFIX_SHA)
        form = text.split("private func publishingForm", 1)[1].split("private var mayClear", 1)[0]
        step0 = form.split("clamp(wizardStep) == 0", 1)[1].split("clamp(wizardStep) == 1", 1)[0]
        step1 = form.split("clamp(wizardStep) == 1", 1)[1].split("clamp(wizardStep) == 2", 1)[0]
        step2 = form.split("clamp(wizardStep) == 2", 1)[1].split("publishModes.saveLocal", 1)[0]
        for token in ["publishParity.activity.title", "publishModes.addressName", "publishModes.activity.start",
                      "publishModes.activity.timeRange.open", "publishParity.activity.type"]:
            self.assertIn(token, step0)
        for token in ["publishParity.activity.description", "publishModes.template", "publishModes.collaborators", "publishModes.addTicket"]:
            self.assertNotIn(token, step0)
        for token in ["publishParity.activity.description", "publishModes.cover", "activityTemplate.open", "ActivityCoverAuthoringSection"]:
            self.assertIn(token, step1)
        self.assertNotIn("publishModes.activity.timeRange.open", step1)
        for token in ["publishModes.collaborators", "publishParity.ticket.name", "publishModes.addTicket", "requiresIdentity"]:
            self.assertIn(token, step2)
        self.assertIn("submissionResult", form[form.index("publishModes.saveLocal"):])
        self.assertIn("ActivityPublishingWizardNavigation", form)
        self.assertNotIn("publishModes.activity.review", form)
        self.assertIn("service?.mutationsConfigured != true", text)
        self.assertIn("service.prepareActivity(draft, session: account)", text)
        self.assertIn("service.submit(review)", text)
        self.assertIn("invalidateReviews()", text)
        self.assertIn('wizardStep = 0; wizardBlock = nil; abandonConfirm = false', text)
        self.assertIn("结果未知，原请求保持锁定。查看项目不会确认本次请求，也不会重新发送。", text)
        self.assertIn("ActivityPublishingWizard.located(ActivityPublishingWizard.steps.count, draft)", text)
        self.assertIn("ActivityPublishingWizard.located(wizardStep, draft)", text)
        navigation = read("App/ActivityPublishingWizardView.swift")
        self.assertIn("publishModes.activity.review", navigation)
        self.assertIn("current < ActivityPublishingWizard.steps.count - 1", navigation)
        self.assertIn("publishModes.cancel", navigation)
        self.assertNotIn("prepareActivity", navigation)
        self.assertNotIn("service.submit", navigation)

    def test_forward_only_one_complete_step_and_restore_lands_on_first_gap(self):
        draft = blank()
        self.assertEqual(resume(draft), 0)
        self.assertIsNone(advance(0, draft))
        self.assertEqual(located(2, draft), 0)
        self.assertEqual([item["state"] for item in progress(0)], ["current", "todo", "todo"])
        self.assertEqual(blocking(0, draft), "name")
        draft["name"] = "  "
        self.assertEqual(blocking(0, draft), "name")
        draft["name"] = "城墙夜巡"
        self.assertEqual(blocking(0, draft), "addressName")
        draft["addressName"] = "西安城墙"
        draft["start"] = "not-a-date"
        self.assertEqual(blocking(0, draft), "startDate")
        draft["start"] = "2030-02-31 09:00:00"
        self.assertEqual(blocking(0, draft), "startDate")
        draft["start"] = "2030-01-01 09:00"
        draft["end"] = "2030-01-01 09:00:00"
        self.assertEqual(blocking(0, draft), "endDate")
        draft["end"] = "2030-01-01T18:00:00"
        draft["categoryIDs"] = [0]
        self.assertEqual(blocking(0, draft), "categoryIds")
        draft["categoryIDs"] = [3]
        self.assertEqual(advance(0, draft), 1)
        self.assertIsNone(advance(1, draft))
        self.assertEqual(located(99, draft), 1)
        self.assertEqual(blocking(1, draft), "description")
        draft["description"] = "沿城墙走一圈"
        self.assertEqual(blocking(1, draft), "templateId")
        draft["templateID"] = 41
        self.assertEqual(blocking(1, draft), "imgUrl")
        draft["coverURL"] = "fixture://cover"
        self.assertEqual(advance(1, draft), 2)
        self.assertIsNone(advance(2, draft))
        self.assertEqual([item["state"] for item in progress(2)], ["done", "done", "current"])
        self.assertEqual(retreat(2), 1)
        self.assertEqual(draft["name"], "城墙夜巡")
        self.assertEqual(blocking(2, draft), "ticket")
        draft["tickets"] = [ticket(name="")]
        self.assertEqual(blocking(2, draft), "ticketName0")
        draft["tickets"] = [ticket(price="-1")]
        self.assertEqual(blocking(2, draft), "ticketPrice0")
        draft["tickets"] = [ticket(stock="0")]
        self.assertEqual(blocking(2, draft), "ticketStock0")
        draft["tickets"] = [ticket(end="2030-01-01 08:00:00")]
        self.assertEqual(blocking(2, draft), "ticketEnd0")
        draft["tickets"] = [ticket(end="2030-01-02 18:00:00")]
        self.assertEqual(blocking(2, draft), "ticketEnd0")
        draft["collaborators"] = [71, 71]
        draft["tickets"] = [ticket()]
        self.assertEqual(blocking(2, draft), "collaborators")
        draft["collaborators"] = []
        self.assertTrue(complete(2, draft))
        self.assertEqual(resume(draft), 2)
        self.assertEqual(located(0, draft), 0)
        self.assertTrue(wire_accepts(draft))
        draft["name"] = ""
        self.assertFalse(wire_accepts(draft))
        self.assertEqual(located(2, draft), 0)
        self.assertIsNone(advance(2, draft))

    def test_ready_draft_accepts_review_and_unknown_keys_do_not_jump(self):
        draft = ready()
        self.assertTrue(wire_accepts(draft))
        self.assertEqual(resume(draft), 2)
        self.assertIsNone(advance(2, draft))
        self.assertEqual(resolve("name"), 0)
        self.assertEqual(resolve("startDate"), 0)
        self.assertEqual(resolve("description"), 1)
        self.assertEqual(resolve("imgUrl"), 1)
        self.assertEqual(resolve("ticketName0"), 2)
        self.assertEqual(resolve("ticketEnd1"), 2)
        self.assertEqual(resolve("collaborators"), -1)
        self.assertEqual(resolve("identityRealName"), -1)
        self.assertEqual(clamp(-4), 0)
        self.assertEqual(progress(1)[0]["state"], "done")
        self.assertEqual(progress(1)[1]["title"], "活动内容")

    def test_wire_agreement_on_mutants(self):
        base = ready()
        mutants = []
        for key, value in [("name", " "), ("description", ""), ("coverURL", " \n"), ("addressName", ""),
                           ("start", "2030-01-01"), ("end", "2030-01-01 00:00:00"), ("templateID", None),
                           ("categoryIDs", []), ("collaborators", [0]), ("tickets", [])]:
            draft = ready()
            draft[key] = value
            mutants.append(draft)
        bad_ticket = ready()
        bad_ticket["tickets"] = [ticket(stock=" 7")]
        mutants.append(bad_ticket)
        for draft in [base, *mutants]:
            self.assertEqual(wire_accepts(draft), all(complete(index, draft) for index in range(3)))
            self.assertEqual(blocking(resume(draft), draft) is None, wire_accepts(draft))


if __name__ == "__main__":
    unittest.main()

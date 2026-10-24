"""Linux source contracts for exclusive C11 ops-support Core projections.

These checks do not compile or execute Swift. XCTest on Linux is NOT_RUN.
App / XCTest / CI = NOT_RUN. This is not 100%.
"""
from pathlib import Path
import hashlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE_FILES = [
    "Core/SupportEventLocator.swift",
    "Core/SupportLookupEntry.swift",
    "Core/CompensationEntryProjection.swift",
    "Core/DataDeletionEvidenceTable.swift",
    "Core/ReviewResultVisibilityAdapter.swift",
    "Core/VersionedLocaleDisplay.swift",
    "Core/ProfileOrderEventSourceInjection.swift",
    "Core/ProfileOrderEventHost.swift",
]
TEST_FILES = [
    "Tests/CoreTests/SupportEventLocatorTests.swift",
    "Tests/CoreTests/SupportLookupEntryTests.swift",
    "Tests/CoreTests/CompensationEntryProjectionTests.swift",
    "Tests/CoreTests/DataDeletionEvidenceTableTests.swift",
    "Tests/CoreTests/ReviewResultVisibilityAdapterTests.swift",
    "Tests/CoreTests/VersionedLocaleDisplayTests.swift",
    "Tests/CoreTests/ProfileOrderEventSourceInjectionTests.swift",
    "Tests/CoreTests/ProfileOrderEventHostTests.swift",
]
CONTRACT = "Tests/ContractChecks/test_c11_ops_support_projections.py"
HUNK = "docs/issue5-hunks/C11-ios-dot-hunk.md"
EVENT_SOURCE_HUNK = "docs/issue5-hunks/C11-event-source-inject.hunk"
HOST_HUNK = "docs/issue5-hunks/C11-event-host-inject.hunk"
WHITELIST = CORE_FILES + TEST_FILES + [
    CONTRACT,
    HUNK,
    EVENT_SOURCE_HUNK,
    HOST_HUNK,
    "App/WithdrawalSupportLandingView.swift",
    "App/ProfileOrdersView.swift",
]
EVENT_SOURCE_PARENT = "6272cd2d16957959397ebf68b94a8e1447bdf6c0"
FORBIDDEN_TOUCH = [
    "App/AppSession.swift",
    "App/AppCompositionRoot.swift",
    "Questify.xcodeproj/project.pbxproj",
]
BASE = "origin/migration/native-ios"
PINNED = "76ce1b313af2595f9b7d7ace49040866209c7974"


def git_changed_names():
    names = set()
    commands = [
        ["git", "diff", "--name-only", BASE],
        ["git", "diff", "--name-only", "--cached", BASE],
        ["git", "diff", "--name-only", BASE, "HEAD"],
        ["git", "diff", "--name-only", PINNED],
        ["git", "diff", "--name-only", PINNED, "HEAD"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ]
    for command in commands:
        output = subprocess.check_output(command, cwd=str(ROOT), text=True)
        names.update(line for line in output.splitlines() if line.strip())
    return names


def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


class C11OpsSupportProjectionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in CORE_FILES + TEST_FILES}
        cls.joined = "\n".join(cls.sources.values())
        cls.hunk = (ROOT / HUNK).read_text()

    def test_exclusive_whitelist_files_exist(self):
        for path in WHITELIST:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_git_diff_against_native_ios_equals_whitelist(self):
        self.assertEqual(git_changed_names(), set(WHITELIST), git_changed_names().symmetric_difference(set(WHITELIST)))

    def test_forbidden_files_untouched(self):
        changed = git_changed_names()
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
            self.assertNotIn(path, changed)
            current = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            original = subprocess.check_output(["git", "show", f"{PINNED}:{path}"], cwd=str(ROOT))
            self.assertEqual(current, hashlib.sha256(original).hexdigest(), path)

    def test_first_journey_markers_present(self):
        for path in TEST_FILES:
            text = self.sources[path]
            self.assertIn("testFirstJourney", text, path)
            self.assertIn("RecoverOriginal", text, path)
            self.assertIn("@testable import QuestifyCore", text, path)
        journey = self.sources["Tests/CoreTests/SupportEventLocatorTests.swift"]
        self.assertIn("c11-journey-req", journey)
        self.assertIn("UNKNOWN", journey)
        self.assertIn("APPLIED+SUCCESS", journey)
        self.assertIn("200.00", journey)
        self.assertIn("999.00", journey)
        self.assertIn("member_identity", journey)
        self.assertIn("oms_order", journey)
        self.assertIn("business_audit_event", journey)
        self.assertIn("NOT_RUN", journey)
        self.assertIn("recoverOriginal", journey)

    def test_locate_original_unknown_not_projection_success(self):
        locator = self.sources["Core/SupportEventLocator.swift"]
        self.assertTrue(locator.startswith("import Foundation"))
        self.assertIn("APPLIED+SUCCESS", locator)
        self.assertIn("Optional.none", locator)
        self.assertIn("NSNull()", locator)
        self.assertIn("func locateByRequestId(", locator)
        self.assertIn("func requery(", locator)
        self.assertIn("func recoverOriginal(", locator)
        self.assertIn("func locateByRunId(", locator)
        self.assertIn("func locateByOrderId(", locator)
        self.assertIn("originalIsNotProjectionSuccess", locator)
        self.assertNotIn('return ""', locator)

    def test_missing_request_id_is_optional_none_never_empty_string(self):
        self.assertIn("Optional.none", self.joined)
        self.assertIn("never \"\"", self.joined)
        self.assertIn("NSNull()", self.sources["Core/SupportEventLocator.swift"])
        tests = self.sources["Tests/CoreTests/SupportEventLocatorTests.swift"]
        self.assertIn("testMissingRequestIdStaysOptionalNoneNeverEmptyString", tests)
        self.assertIn('requestID("")', tests)
        self.assertIn("NSNull", tests)

    def test_compensation_pass_in_grant_frozen_not_final(self):
        compensation = self.sources["Core/CompensationEntryProjection.swift"]
        self.assertTrue(compensation.startswith("import Foundation"))
        self.assertIn("business:clubextra:approve", compensation)
        self.assertIn("COMPENSATION_VIEW_DENIED", compensation)
        self.assertIn("pass-in grant", compensation)
        self.assertIn("does not look up tokens", compensation)
        self.assertIn("originalEntryNotReplacedByCurrentFinal", compensation)
        self.assertIn("func requery(", compensation)
        self.assertIn("func recoverOriginal(", compensation)
        self.assertIn("projectFromReachability", compensation)
        self.assertIn("auditTrail.trail", compensation)
        self.assertIn("recoverTrail", compensation)
        self.assertIn("extraApprover.canApproveExtraHours", compensation)
        self.assertIn("clubEditionCompensation.requireFrozenTerms", compensation)
        tests = self.sources["Tests/CoreTests/CompensationEntryProjectionTests.swift"]
        self.assertIn("200.00", tests)
        self.assertIn("999.00", tests)
        self.assertIn("denied viewer must not read audit", tests)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueAuditApplies", tests)
        self.assertIn("testProjectFromReachabilityConsumesPublicFrozenTermsWithoutOccupyingOnDeny", tests)
        self.assertIn("testRecoverTrailReadsExistingUnifiedTrailWithoutWritingAudit", tests)
        self.assertIn("c11-comp-never", tests)

    def test_deletion_evidence_is_table_not_cleaner(self):
        table = self.sources["Core/DataDeletionEvidenceTable.swift"]
        self.assertTrue(table.startswith("import Foundation"))
        self.assertIn("Not a cleaner and not DDL", table)
        self.assertIn("emptyCurrentProjectionIsNeverExisted", table)
        self.assertIn("ACCOUNT_DEREGISTER", table)
        self.assertIn("member_identity", table)
        self.assertIn("REMOVED", table)
        self.assertIn("oms_order", table)
        self.assertIn("ANONYMIZED_RETAINED", table)
        self.assertIn("business_audit_event", table)
        self.assertIn("RETAINED_LEGAL", table)
        self.assertIn("browseDays = 180", table)
        self.assertIn("eventDays = 365", table)
        self.assertIn("npcChatDays = 90", table)
        self.assertIn("npcChatRequestHours = 48", table)
        self.assertIn("roamLocationDays = 30", table)
        self.assertIn("executesCleanup = false", table)
        self.assertIn("writesDDL = false", table)

    def test_review_submit_reject_revise_approve_and_status_ints(self):
        review = self.sources["Core/ReviewResultVisibilityAdapter.swift"]
        self.assertTrue(review.startswith("import Foundation"))
        self.assertIn("PENDING=0 APPROVED=1 REJECTED=2 CANCELLED=3 ESCALATED=4", review)
        self.assertIn("pending = 0", review)
        self.assertIn("approved = 1", review)
        self.assertIn("rejected = 2", review)
        self.assertIn("cancelled = 3", review)
        self.assertIn("escalated = 4", review)
        self.assertIn("flowSubmitRejectReviseApprove", review)
        self.assertIn("currentContentProjectionPublished", review)
        self.assertIn("REJECTED", review)
        tests = self.sources["Tests/CoreTests/ReviewResultVisibilityAdapterTests.swift"]
        self.assertIn("approvedResultVisible", tests)
        self.assertIn("currentContentProjectionPublished: true", tests)

    def test_versioned_locale_cn_us_and_legal_not_run(self):
        locale = self.sources["Core/VersionedLocaleDisplay.swift"]
        self.assertTrue(locale.startswith("import Foundation"))
        self.assertIn("profileVersion = 2", locale)
        self.assertIn("eventTimezoneSource", locale)
        self.assertIn("locale.eventTimezone", locale)
        self.assertIn("waitingSource", locale)
        self.assertIn("timeZone: TimeZone", locale)
        self.assertIn("zh-CN", locale)
        self.assertIn("Asia/Shanghai", locale)
        self.assertIn("yyyy-MM-dd HH:mm:ss", locale)
        self.assertIn("en-US", locale)
        self.assertIn("America/New_York", locale)
        self.assertIn("MMM d, yyyy h:mm a", locale)
        self.assertIn("NOT_RUN", locale)
        self.assertIn("ICP_FILING", locale)
        self.assertIn("PRIVACY_AGREEMENT", locale)
        self.assertIn("USER_AGREEMENT", locale)
        self.assertIn("WECHAT_MINIPROGRAM_REVIEW", locale)
        self.assertIn("APP_STORE_REVIEW", locale)
        self.assertIn("PLAY_STORE_REVIEW", locale)
        self.assertIn("PRODUCTION_CAPACITY", locale)
        self.assertIn("PRODUCTION_DDL", locale)
        self.assertIn("微信支付", locale)
        self.assertIn("Apple IAP", locale)
        self.assertIn("线下核销仍不走 IAP", locale)
        tests = self.sources["Tests/CoreTests/VersionedLocaleDisplayTests.swift"]
        self.assertIn("2026-10-23 20:00:00", tests)
        self.assertIn("2026-10-23T12:00:00Z", tests)

    def test_account_switch_isolation_markers_present(self):
        tests = self.sources["Tests/CoreTests/SupportEventLocatorTests.swift"]
        self.assertIn("testOtherRequestIdDoesNotRewriteOriginalEvents", tests)
        self.assertIn("testInProcessRecoverKeepsOriginalUnknownNotProjectionSuccess", tests)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueWriteApplies", tests)
        self.assertIn("c11-never-seen", tests)
        self.assertIn('locateByRequestId("req-other"', tests)
        self.assertIn("originalMissing(requestId: \"req-other\")", tests)
        compensation = self.sources["Tests/CoreTests/CompensationEntryProjectionTests.swift"]
        self.assertIn("testOtherViewerDoesNotRewriteFrozenOriginal", compensation)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueAuditApplies", compensation)
        self.assertIn("c11-comp-never", compensation)
        self.assertIn("viewerId: 3", compensation)

    def test_waiting_source_unsigned_originals(self):
        locator = self.sources["Core/SupportEventLocator.swift"]
        self.assertIn("WAITING_SOURCE", locator)
        self.assertIn("v12.docx", locator)
        self.assertIn("232.pack", locator)
        self.assertIn("e2d86c4", locator)
        self.assertIn("v12DocxPresent: Bool { false }", locator)
        self.assertIn("pack232Present: Bool { false }", locator)
        self.assertIn("unpushedIosSHAPresent: Bool { false }", locator)

    def test_no_shared_forbidden_owners(self):
        for forbidden in [
            "AppSession", "AppCompositionRoot", "project.pbxproj",
            "PlayExperienceCoordinator", "PlayExperienceService(",
            "PlayNode", "RouteEffects", "TopicRouteRuntime",
            "CmsTopic", "DynamicAttributeAuthoring",
            "Localizable.xcstrings", "URLSession", "HTTPTransport",
            "CLLocation", "fake GPS", "NSLocalizedString",
            "import SwiftUI", "@MainActor",
        ]:
            self.assertNotIn(forbidden, self.joined, forbidden)
        for token in ["JWT", "RBAC"]:
            self.assertNotIn(token, self.joined, token)
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertTrue(text.startswith("import Foundation"), path)
            self.assertNotIn("import SwiftUI", text)
            self.assertNotIn("@MainActor", text)

    def test_hunk_lists_exact_pbx_file_refs(self):
        self.assertIn(ident("Core/SupportEventLocator.swift"), self.hunk)
        self.assertIn(ident("build:Core/SupportEventLocator.swift"), self.hunk)
        self.assertIn("D579A9832347C0C626BE58BE", self.hunk)
        self.assertIn("0FD49EE8EC846933EEC26AC1", self.hunk)
        self.assertIn("Core/SupportEventLocator.swift", self.hunk)
        self.assertIn("Tests/CoreTests/VersionedLocaleDisplayTests.swift", self.hunk)
        self.assertIn("Do not edit pbxproj", self.hunk)
        self.assertIn("WAITING_SOURCE", self.hunk)
        self.assertIn("NOT_RUN", self.hunk)
        self.assertIn("not 100%", self.hunk.lower())
        self.assertNotIn("IPHONEOS_DEPLOYMENT_TARGET = 1", self.hunk)

    def test_support_lookup_entry_wraps_locator_beside_existing_reads(self):
        entry = self.sources["Core/SupportLookupEntry.swift"]
        tests = self.sources["Tests/CoreTests/SupportLookupEntryTests.swift"]
        landing = (ROOT / "App/WithdrawalSupportLandingView.swift").read_text()
        self.assertTrue(entry.startswith("import Foundation"))
        self.assertIn("struct SupportLookupEntry", entry)
        self.assertIn("SupportEventLocator", entry)
        self.assertIn("locateByRunId", entry)
        self.assertIn("locateByOrderId", entry)
        self.assertIn("originalMissing", entry)
        self.assertIn("WithdrawalSupportSnapshot", entry)
        self.assertIn("OwnedOrderReadRoute", entry)
        self.assertIn("does not send", entry)
        self.assertNotIn("struct WithdrawalSupportLandingView", entry)
        self.assertIn("struct WithdrawalSupportLandingView", landing)
        self.assertIn('Section("withdrawal.support.balance")', landing)
        self.assertIn('Section("withdrawal.support.notReceived")', landing)
        self.assertIn("SupportLookupEntry", landing)
        self.assertIn("entry.appear()", landing)
        self.assertIn("entry.lookupByOrderId(", landing)
        self.assertIn("func firstOrderID(", landing)
        self.assertIn("composition.located.orderId == requested", landing)
        self.assertIn("Self.firstOrderID(composition.located.originalEvents) == requested", landing)
        self.assertIn("lookedUpOrderID = requested", landing)
        self.assertIn("lookedUpOrderID = nil", landing)
        self.assertNotIn("lookedUpOrderID = composition", landing)
        self.assertNotIn("lookedUpOrderID = Self.firstOrderID", landing)
        self.assertNotIn("InMemoryOriginalEventSource", landing)
        self.assertNotIn("SupportEventLocator(", landing)
        self.assertNotIn("gradient", landing.lower())
        self.assertNotIn("append(", entry)
        self.assertIn("testFirstJourneySupportLookupBesideWithdrawalAndOrderRecoverOriginal", tests)
        self.assertIn("originalMissing(requestId: \"ORDER:9\")", tests)
        self.assertIn("originalMissing(requestId: \"RUN:77\")", tests)
        self.assertNotIn("struct WithdrawalSupportLandingView", tests)

    def test_profile_orders_page_looks_up_the_opened_order(self):
        page = (ROOT / "App/ProfileOrdersView.swift").read_text()
        landing = (ROOT / "App/WithdrawalSupportLandingView.swift").read_text()
        self.assertIn("struct ProfileOrdersView", page)
        self.assertIn("ForEach(visible)", page)
        self.assertIn("ProfileOrderRow(order: order", page)
        self.assertIn("struct ProfileOrderDetailView", page)
        self.assertIn("SupportLookupEntry", page)
        self.assertIn("entry.appear()", page)
        self.assertIn("entry.lookupByOrderId(", page)
        self.assertIn("onAppear { appearOrderSupport() }", page)
        self.assertIn("lookupOpenedOrder($0)", page)
        self.assertIn(".task(id: id) { onOpenedOrder?(id) }", page)
        self.assertIn("func firstOrderID(", page)
        self.assertIn("composition.located.orderId == requested", page)
        self.assertIn("Self.firstOrderID(composition.located.originalEvents) == requested", page)
        self.assertIn("lookedUpOrderID = requested", page)
        self.assertIn("lookedUpOrderID = nil", page)
        self.assertIn("lookedUpOrderID == Int64(id)", page)
        self.assertIn('accessibilityIdentifier("profile.orders.supportLookup")', page)
        self.assertNotIn("lookedUpOrderID = composition", page)
        self.assertNotIn("lookedUpOrderID = Self.firstOrderID", page)
        self.assertNotIn("lookedUpOrderID = order", page)
        self.assertNotIn("InMemoryOriginalEventSource", page)
        self.assertNotIn("SupportEventLocator(", page)
        self.assertNotIn("gradient", page.lower())
        self.assertNotIn("glow", page.lower())
        self.assertNotIn("audit-log", page.lower())
        self.assertNotIn("admin/audit", page.lower())
        appear = page.split("func appearOrderSupport()", 1)[1].split("func lookupOpenedOrder(", 1)[0]
        self.assertNotIn("lookupByOrderId", appear)
        self.assertNotIn("lookupOpenedOrder", appear)
        self.assertIn("struct WithdrawalSupportLandingView", landing)
        self.assertIn("entry.lookupByOrderId(", landing)

    def test_linux_xctest_is_explicitly_not_run(self):
        self.assertIn("XCTest on Linux is NOT_RUN", Path(__file__).read_text())
        self.assertIn("not 100%", Path(__file__).read_text())
        self.assertIn("App / XCTest / CI = NOT_RUN", Path(__file__).read_text())

    def test_event_source_injection_accepts_explicit_rows_and_stays_quiet(self):
        source = self.sources["Core/ProfileOrderEventSourceInjection.swift"]
        tests = self.sources["Tests/CoreTests/ProfileOrderEventSourceInjectionTests.swift"]
        hunk = (ROOT / EVENT_SOURCE_HUNK).read_text()
        self.assertTrue(source.startswith("import Foundation"))
        self.assertIn("struct ProfileOrderEventSourceInjection", source)
        self.assertIn("func entry()", source)
        self.assertIn("func lookupOpenedOrder(", source)
        self.assertIn("func recoverOriginal(", source)
        self.assertIn("SupportLookupEntry", source)
        self.assertIn("SupportEventLocator", source)
        self.assertIn("originalMissing", source)
        self.assertIn("first ORDER id", source)
        self.assertIn("guard let events else { return nil }", source)
        self.assertIn("Not a second audit store", source)
        self.assertNotIn("audit-log", source.lower())
        self.assertNotIn("admin/audit", source.lower())
        self.assertNotIn("gradient", source.lower())
        self.assertNotIn("glow", source.lower())
        self.assertIn("testFirstJourneyOpenedOrderPassesLoadedEventsAndRecoverOriginal", tests)
        self.assertIn('originalMissing(requestId: "ORDER:9")', tests)
        self.assertIn('originalMissing(requestId: "ORDER:501")', tests)
        self.assertIn("testAbsentSourceStaysQuietAndDoesNotInventEvents", tests)
        self.assertIn("DO NOT APPLY", hunk)
        self.assertIn("AppSession", hunk)
        self.assertIn("E4EBDBD8004184448257DAD7", hunk)
        self.assertIn("0ACC7EDB105A7757E4509C27", hunk)
        self.assertIn("Not 100%", hunk)
        self.assertIn("NOT_RUN", hunk)
        untouched = [
            "App/ProfileOrdersView.swift",
            "App/WithdrawalSupportLandingView.swift",
            "Core/SupportLookupEntry.swift",
            "App/AppSession.swift",
            "App/AppCompositionRoot.swift",
            "Questify.xcodeproj/project.pbxproj",
        ]
        for path in untouched:
            current = (ROOT / path).read_bytes()
            original = subprocess.check_output(["git", "show", f"{EVENT_SOURCE_PARENT}:{path}"], cwd=str(ROOT))
            self.assertEqual(current, original, path)

    def test_event_host_reads_owned_order_then_original_event(self):
        source = self.sources["Core/ProfileOrderEventHost.swift"]
        tests = self.sources["Tests/CoreTests/ProfileOrderEventHostTests.swift"]
        hunk = (ROOT / HOST_HUNK).read_text()
        landing = (ROOT / "App/WithdrawalSupportLandingView.swift").read_text()
        self.assertTrue(source.startswith("import Foundation"))
        self.assertIn("struct ProfileOrderEventHost", source)
        self.assertNotIn("struct ProfileOrderEventSourceInjection", source)
        self.assertNotIn("init(events:", source)
        self.assertIn("api/registration/info", source)
        self.assertIn("api/registration/original-event", source)
        self.assertLess(source.index("api/registration/info"), source.index("api/registration/original-event"))
        self.assertIn("infoID == openedOrderID", source)
        self.assertIn("Self.firstOrderID(rows) == Int64(openedOrderID)", source)
        self.assertIn("lookupOpenedOrder(openedOrderID)", source)
        self.assertIn("ProfileOrder fields are not OriginalAuditEvent", source)
        self.assertNotIn("ProfileOrder(", source)
        self.assertNotIn("audit-log", source.lower())
        self.assertNotIn("locateByRunId", source)
        self.assertNotIn("gradient", source.lower())
        self.assertNotIn("glow", source.lower())
        self.assertIn("testFirstJourneyOwnedOrderReadsInfoThenOriginalEventAndRecoverOriginal", tests)
        self.assertIn("recoverOriginal", tests)
        self.assertIn("api/registration/info", tests)
        self.assertIn("api/registration/original-event", tests)
        self.assertIn("DO NOT APPLY", hunk)
        self.assertIn("AppSession", hunk)
        self.assertIn("AppCompositionRoot", hunk)
        self.assertIn("project.pbxproj", hunk)
        self.assertIn("C7BA648D253BCD7E4FE8CCC4", hunk)
        self.assertIn("CAF2E94E0388E741B99F46FD", hunk)
        self.assertIn("ProfileOrderEventHost.open", hunk)
        self.assertIn("api/registration/info", hunk)
        self.assertIn("api/registration/original-event", hunk)
        self.assertIn("withdrawal.support.balance", hunk)
        self.assertIn("withdrawal.support.notReceived", hunk)
        self.assertIn("NOT_RUN", hunk)
        self.assertIn("Not 100%", hunk)
        for path in [
            "App/AppSession.swift",
            "App/AppCompositionRoot.swift",
            "App/OwnedOrderComposition.swift",
            "App/ProfileOrdersView.swift",
            "Questify.xcodeproj/project.pbxproj",
        ]:
            self.assertNotIn("ProfileOrderEventHost", (ROOT / path).read_text(), path)
        self.assertIn('Section("withdrawal.support.balance")', landing)
        self.assertIn('Section("withdrawal.support.notReceived")', landing)
        self.assertNotIn("ProfileOrderEventHost", landing)

    def test_sha256_payload_covers_whitelist(self):
        digest = hashlib.sha256()
        for path in WHITELIST:
            digest.update(path.encode())
            digest.update((ROOT / path).read_bytes())
        self.assertEqual(len(digest.hexdigest()), 64)


if __name__ == "__main__":
    unittest.main()

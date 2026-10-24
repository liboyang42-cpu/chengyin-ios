"""Linux source contracts for exclusive C09 notify / webhook Core projections.

These checks do not compile or execute Swift. XCTest on Linux is NOT_RUN.
App / XCTest / CI = NOT_RUN. This is not 100%.
"""
from pathlib import Path
import hashlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = "origin/migration/native-ios"
CORE_FILES = [
    "Core/DevicePushRegistrationLifecycle.swift",
    "Core/ImmutableReceiptProducer.swift",
    "Core/NativeChannelMessageActionEntry.swift",
    "Core/AttachmentReviewProducer.swift",
    "Core/WebhookSsrfHopGuard.swift",
    "Core/WebhookDeliveryLogProducer.swift",
    "Core/WebhookSameEventRetry.swift",
]
TEST_FILES = [
    "Tests/CoreTests/DevicePushRegistrationLifecycleTests.swift",
    "Tests/CoreTests/ImmutableReceiptProducerTests.swift",
    "Tests/CoreTests/NativeChannelMessageActionEntryTests.swift",
    "Tests/CoreTests/AttachmentReviewProducerTests.swift",
    "Tests/CoreTests/WebhookSsrfHopGuardTests.swift",
    "Tests/CoreTests/WebhookDeliveryLogProducerTests.swift",
    "Tests/CoreTests/WebhookSameEventRetryTests.swift",
]
CONTRACT = "Tests/ContractChecks/test_c09_notify_webhook_projections.py"
HUNK = "docs/issue5-hunks/C09-ios-dot-hunk.md"
WHITELIST = CORE_FILES + TEST_FILES + [CONTRACT, HUNK]
FORBIDDEN_TOUCH = [
    "App/AppSession.swift",
    "App/AppCompositionRoot.swift",
    "Questify.xcodeproj/project.pbxproj",
]
ATTACHMENT_TYPES = [
    "IMAGE", "VIDEO", "AUDIO", "FILE", "LOCATION", "STICKER", "LINK", "CARD",
    "POLL", "CONTACT", "VOICE_NOTE", "LIVE", "MUSIC", "GIF", "ALBUM", "MINI_PROGRAM",
]
PBX_IDS = [
    "A1FF02D3570BBB42E0A5DCE0", "4B907AEA0AC50364B258EE03",
    "B967E4281054092D40D1BF28", "A533EC68B202FE78859E47C7",
    "911F86EFD0EBF5439E69FE21", "9431C5D1363AB26D14C84A67",
    "3784841CCD3F826F84FE5936", "176B0A8F3147601FB8E89989",
    "B0E6F3FB552B81A64EFA45EC", "5D16B639E0B3F68C5DE081E1",
    "92A3F8A7B9336FD7154202DC", "7DEB2935B2F97D5575670E4F",
]


def git_changed_names():
    names = set()
    commands = [
        ["git", "diff", "--name-only", BASE],
        ["git", "diff", "--name-only", "--cached", BASE],
        ["git", "diff", "--name-only", BASE, "HEAD"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ]
    for command in commands:
        output = subprocess.check_output(command, cwd=str(ROOT), text=True)
        names.update(line for line in output.splitlines() if line.strip())
    return names


class C09NotifyWebhookProjectionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in CORE_FILES + TEST_FILES}
        cls.joined = "\n".join(cls.sources.values())
        cls.hunk = (ROOT / HUNK).read_text()

    def test_exclusive_whitelist_files_exist(self):
        for path in WHITELIST:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_git_diff_against_native_ios_equals_whitelist(self):
        self.assertEqual(git_changed_names(), set(WHITELIST), git_changed_names() ^ set(WHITELIST))

    def test_first_journey_markers_present(self):
        for path in TEST_FILES:
            text = self.sources[path]
            self.assertIn("testFirstJourney", text, path)
            self.assertIn("RecoverOriginal", text, path)
            self.assertIn("originalRequestID", text, path)
        journey = self.sources["Tests/CoreTests/WebhookSameEventRetryTests.swift"]
        for expected in [
            "testFirstJourneyFixtureWebhookEvtEPinSignedLogRetryDisableRevokeRecoverOriginal",
            "evt-E",
            "PIN",
            "dlv-evt-E",
            "nonce-E",
            "fixture-hmac-c09-not-production",
            "STATUS_SKIPPED_DISABLED",
            "STATUS_SKIPPED_REVOKED",
            "UNKNOWN_NOT_RECOVERED",
            "treatsAppliedProjectionAsOriginalProof",
            "recoverOriginal",
            "recoverUnknown",
        ]:
            self.assertIn(expected, journey)

    def test_account_switch_isolation_markers_present(self):
        receipt = self.sources["Tests/CoreTests/ImmutableReceiptProducerTests.swift"]
        devices = self.sources["Tests/CoreTests/DevicePushRegistrationLifecycleTests.swift"]
        self.assertIn("testOtherRequestDoesNotRewriteOriginalPin", receipt)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenAcceptApplies", receipt)
        self.assertIn("testUnusedOfflineReopenOfNeverSeenDoesNotOccupyThenUniqueAcceptApplies", receipt)
        self.assertIn("testPersistOriginalRequiresImSendAndRecoverFromJournalReadsExistingClientMessageId", receipt)
        self.assertIn("evt-recover-never-c09", receipt)
        self.assertIn("testOtherDeviceDoesNotRewriteOriginalRegistration", devices)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueRegisterApplies", devices)
        self.assertIn("testUnusedRevokeOfNeverSeenDoesNotOccupyThenUniqueRegisterApplies", devices)
        self.assertIn("dev-recover-never-c09", devices)
        self.assertIn("fingerprintConflict(requestId: \"evt-E\")", receipt)
        self.assertIn("dev-other", devices)
        ssrf = self.sources["Tests/CoreTests/WebhookSsrfHopGuardTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenPublicHopAllows", ssrf)
        self.assertIn("evt-ssrf-never-c09", ssrf)
        attachments = self.sources["Tests/CoreTests/AttachmentReviewProducerTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueSubmitApplies", attachments)
        self.assertIn("testUnusedDecideOfNeverSeenDoesNotOccupyThenUniqueSubmitApplies", attachments)
        self.assertIn("att-recover-never-c09", attachments)
        delivery = self.sources["Tests/CoreTests/WebhookDeliveryLogProducerTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueDeliverApplies", delivery)
        self.assertIn("testUnusedRequireOriginalOfNeverSeenDoesNotOccupyThenUniqueDeliverApplies", delivery)
        self.assertIn("evt-dlv-never-c09", delivery)
        retry = self.sources["Tests/CoreTests/WebhookSameEventRetryTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueDeliverApplies", retry)
        self.assertIn("testUnusedRetrySameEventOfNeverSeenDoesNotOccupyThenUniqueDeliverApplies", retry)
        self.assertIn("evt-retry-never-c09", retry)

    def test_core_isolation_contracts(self):
        kernel = self.sources["Core/ImmutableReceiptProducer.swift"]
        self.assertTrue(kernel.startswith("import Foundation"))
        self.assertIn("JSON null", kernel)
        self.assertIn("Optional.none", kernel)
        self.assertIn("WAITING_SOURCE", kernel)
        self.assertIn("v12.docx", kernel)
        self.assertIn("232.pack", kernel)
        self.assertIn("e2d86c4", kernel)
        self.assertIn("v12DocxPresent: Bool { false }", kernel)
        self.assertIn("pack232Present: Bool { false }", kernel)
        self.assertIn("unpushedIosSHAPresent: Bool { false }", kernel)
        self.assertIn("func recoverUnknown(", kernel)
        self.assertIn("func recoverOriginal(", kernel)
        self.assertIn("recoverFromJournal", kernel)
        self.assertIn("func projectOriginalSend", kernel)
        self.assertIn("exactDigest", kernel)
        self.assertIn("[0-9a-f]{64}", kernel)
        self.assertIn("LEGACY", kernel)
        self.assertIn("WRONG_OPERATION", kernel)
        self.assertIn("ACTOR_MISMATCH", kernel)
        self.assertIn("CHANNEL_MISMATCH", kernel)
        self.assertIn("im.readSentMessage", kernel)
        self.assertIn("im.send", kernel)
        self.assertIn("func sendOriginal(", kernel)
        self.assertIn("im.send.originalCommand", kernel)
        self.assertIn("IM_OPERATION_NOT_SEND", kernel)
        self.assertIn("treatsAppliedProjectionAsOriginalProof", kernel)
        self.assertIn("return false", kernel)
        self.assertIn("UNKNOWN_NOT_RECOVERED", kernel)
        self.assertIn("APPLIED+CURRENT", kernel)
        attachments = self.sources["Core/AttachmentReviewProducer.swift"]
        for name in ATTACHMENT_TYPES:
            self.assertIn(f'"{name}"', attachments)
        self.assertIn("CaseIterable", attachments)
        self.assertIn("treatsVisibleProjectionAsApproval", attachments)
        devices = self.sources["Core/DevicePushRegistrationLifecycle.swift"]
        self.assertIn("SANDBOX", devices)
        self.assertIn("PRODUCTION_LABEL", devices)
        self.assertIn("fixture-", devices)
        self.assertIn("REVOKED_OR_DISABLED", devices)
        webhook = self.sources["Core/WebhookDeliveryLogProducer.swift"]
        self.assertIn("RecordingTransport", webhook)
        self.assertIn("never opens sockets", webhook)
        self.assertIn("fixture-", webhook)
        self.assertIn("STATUS_SKIPPED_DISABLED", webhook)
        self.assertIn("STATUS_SKIPPED_REVOKED", webhook)
        self.assertIn("dlv-", webhook)
        self.assertIn("import CryptoKit", webhook)
        ssrf = self.sources["Core/WebhookSsrfHopGuard.swift"]
        self.assertIn("maxHops = 3", ssrf)
        self.assertIn("httpsPort = 443", ssrf)
        self.assertIn("rejectUnresolved", ssrf)
        self.assertIn("Does not resolve DNS", ssrf)
        retry = self.sources["Core/WebhookSameEventRetry.swift"]
        self.assertIn("dlv-{eventId}", retry)
        self.assertIn("func recoverUnknown(", retry)
        retry_src = retry
        self.assertIn("mintedNewRequest", retry_src)

    def test_no_shared_forbidden_owners(self):
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
            self.assertNotIn(path, git_changed_names())
        for forbidden in [
            "AppSession", "AppCompositionRoot", "project.pbxproj",
            "Localizable.xcstrings", "NativeWebhook", "HTTPTransport",
            "URLSession", "RouteEffects", "TopicRouteRuntime", "CmsTopic",
            "PlayExperience", "@MainActor", "import SwiftUI", "CLLocation",
            "NSLocalizedString", "ImService", "HttpWebhookTransport",
            "IImService",
        ]:
            self.assertNotIn(forbidden, self.joined)
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertTrue(text.startswith("import Foundation"), path)
            self.assertNotIn("import SwiftUI", text)
            self.assertNotIn("@MainActor", text)
            self.assertNotIn("URLSession", text)

    def test_hunk_lists_exact_pbx_file_refs(self):
        for path in CORE_FILES + TEST_FILES:
            self.assertIn(path, self.hunk)
        for ident in PBX_IDS:
            self.assertIn(ident, self.hunk)
        self.assertIn("Do not edit pbxproj", self.hunk)
        self.assertIn("WAITING_SOURCE", self.hunk)
        self.assertIn("NOT_RUN", self.hunk)
        self.assertIn("not 100%", self.hunk.lower())
        self.assertIn("sha256(path)[:24].upper()", self.hunk)
        self.assertIn('sha256("build:"+path)[:24].upper()', self.hunk)

    def test_linux_xctest_is_explicitly_not_run(self):
        self.assertIn("XCTest on Linux is NOT_RUN", Path(__file__).read_text())
        self.assertIn("not 100%", Path(__file__).read_text())
        for path in TEST_FILES:
            self.assertIn("@testable import QuestifyCore", self.sources[path])
            self.assertNotIn("@MainActor", self.sources[path])

    def test_message_action_entry_does_not_add_a_second_search_chain(self):
        entry = self.sources["Core/NativeChannelMessageActionEntry.swift"]
        self.assertIn("func send(", entry)
        self.assertIn("func edit(", entry)
        self.assertIn("func recall(", entry)
        self.assertIn("func pin(", entry)
        self.assertNotIn("func search", entry)
        self.assertNotIn("searchOriginal", entry)
        self.assertNotIn("channelMessageSearch", entry)
        self.assertNotIn("NativeChannelMessageSearch", entry)

    def test_sha256_payload_covers_whitelist(self):
        digest = hashlib.sha256()
        for path in WHITELIST:
            digest.update(path.encode())
            digest.update((ROOT / path).read_bytes())
        self.assertEqual(len(digest.hexdigest()), 64)


if __name__ == "__main__":
    unittest.main()

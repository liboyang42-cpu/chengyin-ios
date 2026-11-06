"""Portable source-contract checks only; these do not execute Swift or a backend."""
from pathlib import Path
import json
import os
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = Path(os.environ.get("APPROVED_RELEASE_BASE_ROOT", str(ROOT)))

def source(path):
    candidate = ROOT / path
    return (candidate if candidate.exists() else BASE / path).read_text()

class ApprovedReleaseOriginalRecoveryContractTests(unittest.TestCase):
    def testNormalEditorUsesExistingReadSectionAndItsSingleRecoveryEntry(self):
        self.assertIn("ApprovedReleaseAuthorReadSection(model: model, controller: approvedRelease)", source("App/ProjectEditView.swift"))
        host = source("App/ApprovedReleaseAuthorPresentation.swift")
        self.assertEqual(host.count("ApprovedReleaseOriginalRecoverySection(model: model)"), 1)

    def testRecoveryReaderHasNoPublicationOrPreparationControls(self):
        value = source("App/ApprovedReleaseOriginalRecovery.swift")
        reader = value.split("@MainActor final class Reader: ObservableObject", 1)[1].split("private let model: ProjectEditModel", 1)[0]
        for token in [".prepare(", ".publish(", ".review(", ".claim(", ".submit(", ".retryExact(", ".begin(", ".clear("]:
            self.assertNotIn(token, reader)
        self.assertIn("private let flow: ApprovedTopicReleasePublishFlow", reader)

    def testOpeningRetainsOriginalOwnerJournalAndEditorVisit(self):
        value = source("App/ApprovedReleaseOriginalRecovery.swift")
        for token in ["model.ownsVisit", "model.editorIncarnation == opening.incarnation", "identity == opening.identity", "snapshot == opening.snapshot", "source === opening.source", "model.coordinator.releasePublicationJournal === opening.journal", "ProjectEditLocalStore.exactPending(current, original)"]:
            self.assertIn(token, value)

    def testNewTopicRequiresStrictOriginalAcknowledgment(self):
        value = source("App/ApprovedReleaseOriginalRecovery.swift")
        for token in ["snapshot.draft.owner == .personal", "pending.hasConsistentAcknowledgment", "pending.serverAcknowledged == true", "pending.completedTopicID", "pending.baseline?.draft.owner == .personal"]:
            self.assertIn(token, value)
        self.assertNotIn('draft.preserved["id"]', value)

    def testStatusReadDoesNotRequirePublishOrPrepareAuthority(self):
        value = source("App/ApprovedReleaseOriginalRecovery.swift")
        self.assertIn("source.canCheckStatus(session: session)", value)
        self.assertNotIn("source.canPublish", value)
        self.assertNotIn("releasePreparationSource", value)

    def testInspectionUsesSavedMembershipAndExactJournalSnapshot(self):
        value = source("Core/ApprovedTopicReleasePublicationClient.swift")
        for token in ["snapshot.records.contains(record)", "try journal.read(session: session, topicID: topicID) == snapshot", "inspectedResult?.id == original.id", "snapshot?.records.contains(original.record) == true"]:
            self.assertIn(token, value)

    def testFailedReadKeepsKnownReceiptAndOriginalSummary(self):
        value = source("Core/ApprovedTopicReleasePublicationClient.swift")
        self.assertIn("if !publication, record.receipt != nil", value)
        self.assertIn("updateFromSnapshot(); lastStatusCheckFailed = true", value)
        self.assertIn("else { state = .unconfirmed }", value)

    def testUnknownAndStorageErrorsDoNotEraseOriginalBytes(self):
        value = source("App/ApprovedReleaseOriginalRecovery.swift")
        for token in ["storageIssue = .changed", ".damaged : .unreadable", "reader.state == .unavailable"]:
            self.assertIn(token, value)
        self.assertIn("recovery.storageDamaged", json.loads(source("Resources/ApprovedReleaseOriginalRecovery.xcstrings"))["strings"])
        for token in [".clear(", ".delete(", ".remove("]:
            self.assertNotIn(token, value)

    def testOldBindingsAndBackgroundInvalidateOnlyTheirOriginalPresentation(self):
        value = source("App/ApprovedReleaseOriginalRecovery.swift")
        for token in ["guard presentation?.id == original.id else { return }", "self?.presentation?.readerToken == id", "controller.setActive(phase == .active)", "reader.resultBinding(inspection)"]:
            self.assertIn(token, value)

    def testHistoricalResultUsesCapturedSummaryWithoutFetchingMedia(self):
        value = source("App/ApprovedReleaseSummaryResultView.swift")
        self.assertIn('ApprovedReleaseSummarySection(prepared: original.record.prepared, identifierPrefix: "approvedRelease.history")', value)
        self.assertIn("original.record.receipt", value)
        self.assertNotIn("coverSource:", value)
        for token in ["URLRequest", ".prepare(", ".publish(", ".retryExact("]:
            self.assertNotIn(token, value)

    def testAllRecoveryLabelsHaveEnglishAndSimplifiedChineseValues(self):
        for path in ["Resources/ApprovedReleaseOriginalRecovery.xcstrings", "Resources/ApprovedReleaseHistory.xcstrings"]:
            entries = json.loads(source(path))["strings"]
            self.assertTrue(entries)
            for key, row in entries.items():
                for language in ["en", "zh-Hans"]:
                    unit = row["localizations"][language]["stringUnit"]
                    self.assertEqual(unit["state"], "translated", (key, language))
                    self.assertTrue(unit["value"].strip(), (key, language))

    def testOriginalAppRegressionCoverageIsRetained(self):
        value = source("Tests/AppUnitTests/ApprovedReleaseOriginalRecoveryTests.swift")
        self.assertEqual(len(re.findall(r"func test\w+\(", value)), 22)
        for token in ["testStrictOriginalAcknowledgmentNeedsNoNewBundleOrPrepareEvidence", "testKnownReceiptAndCapturedSummarySurviveFailedLatestRead", "testRestartReopensOriginalDurableIntentWithoutReplayOrMigration", "testLateOldCallbackCannotPersistOrCloseNewPresentation", "testRevocationWhileStatusIsSuspendedCannotSaveLateReceipt"]:
            self.assertIn(token, value)

if __name__ == "__main__":
    unittest.main()

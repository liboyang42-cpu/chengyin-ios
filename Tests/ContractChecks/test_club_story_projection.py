"""Native-local source checks only. These do not compile or execute Swift."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = (ROOT / "Core/ClubStoryPresentation.swift").read_text()
TESTS = (ROOT / "Tests/CoreTests/ClubStoryPresentationTests.swift").read_text()
CONTRACT = (ROOT / "Core/ClubGovernanceContracts.swift").read_text()
SERVICE = (ROOT / "Core/ClubGovernanceService.swift").read_text()


class ClubStoryProjectionContracts(unittest.TestCase):
    def test_exact_sanitized_topic_read_and_existing_permissions(self):
        for expected in ["snapshot.operation == .topicOverview", "snapshot.scope.clubID", "snapshot.scope.topicID",
                         "try snapshot.scope.validate()", "ClubGovernanceValidation.validate(snapshot.value, operation: .topicOverview",
                         "snapshot.permissions?.allows(ClubGovernanceRead.topicOverview.permission"]:
            self.assertIn(expected, CORE)
        self.assertIn('case .topicOverview: return "api/topic/info-to-user"', CONTRACT)
        self.assertIn('case .topicOverview: fields = ["id": .string(String(scope.topicID ?? 0))]', CONTRACT)
        self.assertIn('case .topicSettings, .recruit, .nodeAnswer: return "club:content:manage"', CONTRACT)
        self.assertIn('form: [.topicOverview, .members].contains(operation)', SERVICE)

    def test_projection_uses_only_verified_p057_fields(self):
        for field in ["chaptersList", "nodes", "cmsMemberTemplate", "name", "description", "totalTime", "businessTime",
                      "address", "imgUrl", "title", "validationMethod", "validationMethodStr", "players", "duration", "difficulty"]:
            self.assertIn('["' + field + '"]', CORE)
        for forbidden in ['["answer"]', '["answerReveal"]', '["questionAnswer"]', '["hints"]', '["feedbackText"]',
                          '["latitude"]', '["longitude"]', 'haversine', 'WALK_METERS_PER_MIN', 'Date()', 'URLSession']:
            self.assertNotIn(forbidden, CORE)
        self.assertIn("number.isFinite, number > 0", CORE)
        self.assertIn("if value == .null { return [] }", CORE)
        self.assertIn("rows.allSatisfy({ $0.object != nil })", CORE)

    def test_member_namespace_is_typed_without_public_fallback(self):
        self.assertIn("public let memberTemplateID: MemberPlayTemplateID?", CORE)
        self.assertIn("public let templateID: MemberPlayTemplateID", CORE)
        self.assertIn("flatMap(MemberPlayTemplateID.init(rawValue:))", CORE)
        for forbidden in ["PublicPlayTemplateID", "TemplateAuthoringService", '"api/template/info"', 'scope=my', 'enabled: true']:
            self.assertNotIn(forbidden, CORE)
        self.assertNotIn('"api/', CORE)

    def test_duplicate_identity_is_global_and_all_card_actions_fail_closed(self):
        for expected in ['countIDs(rows.map { $0["id"] })', 'countIDs(nodesByChapter.flatMap { $0 }.map { $0["id"] })',
                         'countIDs(nodesByChapter.flatMap { $0 }.map { $0["cmsMemberTemplate"]["id"] })',
                         "counts[id] == 1", "chapterID != nil && nodeID != nil && templateID != nil",
                         "nodeID: interactive ? nodeID : nil", "memberTemplateID: interactive ? templateID : nil"]:
            self.assertIn(expected, CORE)
        self.assertIn("ClubCustomerHistoryTopicRoute.positiveID", CORE)
        self.assertIn("sequence += 1", CORE)
        self.assertIn("public let id: Int", CORE)

    def test_no_network_or_media_grants_are_created(self):
        for expected in ['parts.scheme == "https"', "parts.user == nil, parts.password == nil", "raw.utf8.count <= 8192",
                         "raw.removingPercentEncoding != nil", "CharacterSet.controlCharacters.contains"]:
            self.assertIn(expected, CORE)
        for forbidden in ["URLRequest", "HTTPTransport", "RuntimeDependencyFactory", "ReadApproval(", "write(", "send("]:
            self.assertNotIn(forbidden, CORE)

    def test_answerability_is_not_permission(self):
        self.assertIn("validationMethod == 1 || validationMethod == 3", CORE)
        self.assertIn("gameplay.isAnswerable, let nodeID = gameplay.nodeID", CORE)
        self.assertIn("snapshot.permissions?.allows(ClubGovernanceRead.nodeAnswer.permission, scope: context.scope) == true", CORE)
        self.assertIn("snapshot?.permissions?.allows(ClubGovernanceRead.nodeAnswer.permission, scope: scope) == true", CORE)
        self.assertIn("nodeID: nodeID", CORE)
        self.assertNotIn("member_spoiler_reveal", CORE)

    def test_routes_bind_current_account_reader_authority_generation_and_exact_content(self):
        for expected in ["self.context == context", "self.snapshotGeneration == snapshotGeneration", "context.accepts(snapshot)",
                         "(context.identity?.accountID ?? 0) > 0", "context.accessIdentity != nil",
                         "chapter.gameplay.filter({ $0.id == gameplay.id }) == [gameplay]",
                         "Self.fingerprint(snapshot.value) == fingerprint", "encoder.outputFormatting = [.sortedKeys]",
                         "Array(SHA256.hash(data: bytes))"]:
            self.assertIn(expected, CORE)
        selection = CORE.split("private struct ClubStorySelection", 1)[1]
        self.assertIn("private let fingerprint: [UInt8]", selection)
        self.assertNotRegex(selection, r"let\s+(record|value|snapshot):\s+ClubGovernance")

    def test_authored_core_coverage_is_explicitly_distinct_from_execution(self):
        expected = ["testTypedProjectionUsesExactSourceFieldsAndMemberTemplateNamespace",
                    "testSequenceContinuesAcrossChaptersAndNodesWithoutGames", "testEmptyChaptersAndMissingOptionalListsRemainDisplayable",
                    "testMalformedNestedListsFailInsteadOfPretendingTheRouteIsEmpty",
                    "testMissingInvalidAndDuplicateIDsPreserveContentButDisableEveryAction",
                    "testEquivalentStringAndIntegerIDsAreDuplicateAndSafeIntegerLimitIsEnforced",
                    "testUnknownAndNonPositiveDurationsAreNotZeroOrInventedEstimates",
                    "testTitleAndCoverFallbackUseOnlyTheSourceNodeAndSafeMedia",
                    "testOnlyTextAndChoiceMethodsCanRequestAnswersAndStillNeedPermission",
                    "testRoutesUseExactMemberTemplateAndNodeIDsWithoutPublicLibraryFallback",
                    "testWrongReadScopeTopicOrMissingAccessCannotCreatePresentation",
                    "testRefreshAccountEpochReaderAuthorityAndScopeChangesExpireBothRoutes",
                    "testAnyChangedSourceFieldAndRemovedOrReplacedRowsExpireSelection",
                    "testPermissionLossDisablesAnswerAndForeignGameplayCannotSelect",
                    "testProjectionNeverRetainsProtectedTemplateAndNodeFields"]
        self.assertEqual(set(re.findall(r"func (test\w+)\(", TESTS)), set(expected))


if __name__ == "__main__":
    unittest.main()

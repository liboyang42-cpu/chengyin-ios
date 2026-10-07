"""Combined-source wiring contracts; not Swift, Apple runtime, or live authority evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class NativeAuthoringUnionContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_bound_and_draft_routes_keep_three_independent_features(self):
        route = self.read('App/ApprovedReleaseCompositionRoute.swift')
        config = self.read('Core/BusinessRuntimeConfiguration.swift')
        self.assertIn('enum ApprovedReleaseCompositionRoute: Equatable', route)
        for case, feature, path in [('reviewSources', 'approvedTopicReviewSources', 'ApprovedTopicReviewPath.sources'),
                                    ('merchantDraftList', 'merchantDraftSelectionList', 'ProjectMerchantDraftPath.list'),
                                    ('merchantDraftResolve', 'merchantDraftSelectionResolve', 'ProjectMerchantDraftPath.resolve')]:
            self.assertEqual(route.count(f'case .{case}: return .{feature}'), 1)
            self.assertEqual(route.count(f'case .{case}: return {path}'), 1)
            self.assertEqual(route.count(f'baseURL.appendingPathComponent({path}).absoluteString {{ self = .{case} }}'), 1)
            self.assertEqual(config.count(f'case .{feature}: paths = [{path}]'), 1)
        self.assertIn('case .merchantDraftList, .merchantDraftResolve:\n            guard ProjectMerchantDraftWire.permitsRequest(value, path: path) else { return nil }; return', route)
        self.assertIn('if case .reviewSources = self { guard Set(value.keys) == ["topicId", "observedAuditTaskId"] else { return nil }; return }', route)
        self.assertIn('self == .reviewPrepare || self == .reviewSubmit', route)
        self.assertIn('ApprovedMerchantReviewSource.decodeSelections(selected)', route)
        self.assertIn('request.httpBodyStream == nil', route)
        self.assertIn('bytes.count <= 4096', route)

    def test_appsession_retains_both_editor_factories_and_exact_draft_grant_pair(self):
        session = self.read('App/AppSession.swift')
        self.assertEqual(session.count('merchantDraftSource: makeProjectMerchantDraftSource()'), 2)
        factory = session.split('private func makeProjectMerchantDraftSource()', 1)[1].split('private var approvedReleaseRuntimeFactory:', 1)[0]
        self.assertIn('let features: Set<BusinessRuntimeFeature> = [.merchantDraftSelectionList, .merchantDraftSelectionResolve]', factory)
        self.assertEqual(factory.count('features.allSatisfy'), 2)
        for token in ['approval: factory.approval(features)', 'transport: factory.client(features)',
                      'currentCredentials:', 'currentCapability:', 'self.projectConfigurationRevision == configurationRevision',
                      'self.compositionViewerRevision == viewerRevision', 'self.currentRuntimeDependencyContext == captured',
                      'self.currentProjectEditSession', 'self.token',
                      'if path == ProjectMerchantDraftPath.list { return current.permits(.merchantDraftSelectionList) }',
                      'if path == ProjectMerchantDraftPath.resolve { return current.permits(.merchantDraftSelectionResolve) }']:
            self.assertIn(token, factory)
        for forbidden in ['.publishingRead', '.publishingWrite', '.projectWrite', '.approvedTopicReviewSubmit', '.approvedTopicReleasePublish']:
            self.assertNotIn(forbidden, factory)

    def test_bound_source_factory_preserves_set_and_fresh_independent_authority(self):
        session = self.read('App/AppSession.swift')
        factory = session.split('private func makeApprovedTopicReviewSource(owner:', 1)[1].split('private func makeApprovedReleasePreparationSource(owner:', 1)[0]
        self.assertIn('let features: Set<BusinessRuntimeFeature> = [.approvedTopicReviewSources, .approvedTopicReviewPrepare, .approvedTopicReviewSubmit, .approvedTopicReviewStatus, .approvedTopicReviewCurrent]', factory)
        for suffix in ['sources', 'prepare', 'submit', 'status', 'current']:
            feature = 'approvedTopicReview' + suffix[0].upper() + suffix[1:]
            self.assertIn(f'if path == ApprovedTopicReviewPath.{suffix} {{ return current.permits(.{feature}) }}', factory)
        for token in ['owner == .personal', '!self.projectConfigurationChanging', 'self.projectConfigurationRevision == configurationRevision',
                      'self.compositionViewerRevision == viewerRevision', 'self.currentRuntimeDependencyContext == captured']:
            self.assertIn(token, factory)
        self.assertNotIn('merchantDraftSelection', factory)

    def test_default_nil_composition_and_creator_grants_remain(self):
        outer = self.read('App/AppCompositionRoot.swift')
        self.assertIn('approvedReleaseConfiguration: @MainActor (RuntimeDependencyContext) -> BusinessRuntimeConfiguration? = { _ in nil }', outer)
        for name, type_name in [('PendingAuthor', 'PendingAuthor'), ('PendingList', 'PendingList'), ('PendingDetail', 'PendingDetail'), ('ConsentRead', 'ConsentRead'), ('ConsentWrite', 'ConsentWrite')]:
            self.assertIn(f'workshopCreator{name}Approval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreator{type_name}Approval? = {{ _ in nil }}', outer)
        core = self.read('Core/ProjectEditCoordinator.swift')
        self.assertIn('merchantDraftSource: (any ProjectMerchantDraftReading)? = nil', core)
        client = self.read('Core/ProjectMerchantDraftClient.swift')
        self.assertIn('approval: OperationEndpointApproval? = nil', client)
        self.assertIn('currentCapability: @escaping (String) -> Bool = { _ in false }', client)

    def test_draft_owner_session_hash_and_authority_projection_remain_exact(self):
        source = self.read('Core/ProjectMerchantDraftSelection.swift')
        client = self.read('Core/ProjectMerchantDraftClient.swift')
        for token in ['Set(v.keys) == basic.union(extraKeys)', 'v["ownerMemberId"]?.integer == accountID',
                      'v["merchantRowId"]?.integer == merchantRowID', 'choice == expected',
                      'v["approvalProof"] == .bool(false)', 'v["usageRightsProof"] == .bool(false)',
                      'v["publicationAuthority"] == .bool(false)', 'HISTORICAL_INPUT_ONLY',
                      'ProjectMerchantDraftWire.validHash(hash)', 'Set(fields.keys) == ["source", "memberTemplateId", "templateContentHash"]']:
            self.assertIn(token, source)
        self.assertIn('var result = node; result.templateID = choice.memberTemplateID; return result', source)
        for token in ['permits(ProjectMerchantDraftPath.list, session: session) && permits(ProjectMerchantDraftPath.resolve, session: session)',
                      'currentCredentials() == credentials, isCurrent(session: session)',
                      'namespace: session.storageNamespace, accountID: session.accountID, path: path']:
            self.assertIn(token, client)

    def test_bound_reference_fields_and_read_only_status_do_not_drop_hashes(self):
        source = self.read('Core/ApprovedMerchantReviewSources.swift')
        route = self.read('App/ApprovedReleaseCompositionRoute.swift')
        for token in ['["kind", "sourceId", "sourceVersion", "contentHash"]', 'MERCHANT_AI_TEMPLATE_SOURCE_V1',
                      'MERCHANT_STORE_FACTS_CONFIRMATION_V1', 'origin.ownerKey == session.ownerKey',
                      'row["ownerMemberId"]?.integer == session.accountID', 'CONFIRMED_HISTORICAL_INPUTS',
                      'row["approvalProof"] == .bool(false)', 'row["publicationAuthority"] == .bool(false)', 'groups.count <= 32']:
            self.assertIn(token, source)
        self.assertIn('expected.formUnion(["observedAuditTaskVersion", "sourceConfigVersion", "snapshotHash", "requestId"])', route)
        self.assertIn('ApprovedTopicReleasePreparation.validHash(hash)', route)

    def test_source_capture_and_confirmation_claim_before_their_own_tasks(self):
        source = self.read('App/ApprovedTopicReviewRequestView.swift')
        capture = source.split('    func captureSources(_ original:', 1)[1].split('    func review(_ capture:', 1)[0]
        confirm = source.split('    func confirm(_ original:', 1)[1].split('    func check(_ original:', 1)[0]
        self.assertLess(capture.index('flow.claimSourceCapture(original)'), capture.index('Task {'))
        self.assertLess(confirm.index('flow.claim(original)'), confirm.index('Task {'))
        self.assertIn('flow.captureSources(claim)', capture)
        self.assertIn('flow.submit(claim)', confirm)

    def test_bound_and_draft_catalogs_are_complete_dedicated_and_explicit_locale(self):
        for table, prefix, count, paths in [
            ('ApprovedMerchantReviewSources', 'topicReview.sources.', 8, ['App/ApprovedMerchantReviewSourceSection.swift', 'App/ApprovedTopicReviewSummarySection.swift']),
            ('ProjectMerchantDraft', 'projectMerchantDraft.', 21, ['App/ProjectMerchantDraftViews.swift', 'App/ProjectEditDetailForms.swift'])]:
            catalog = json.loads(self.read('Resources/' + table + '.xcstrings'))
            self.assertEqual(catalog['sourceLanguage'], 'en')
            self.assertEqual(len(catalog['strings']), count)
            for key, entry in catalog['strings'].items():
                self.assertTrue(key.startswith(prefix))
                self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
                for value in entry['localizations'].values():
                    self.assertEqual(value['stringUnit']['state'], 'translated')
                    self.assertTrue(value['stringUnit']['value'].strip())
            calls = []
            for path in paths:
                text = self.read(path)
                self.assertIn('@Environment(\\.locale)', text)
                for line in text.splitlines():
                    if 'LocalizedStringResource("' + prefix in line:
                        self.assertIn('table: "' + table + '", locale: locale', line)
                        calls.extend(re.findall(r'LocalizedStringResource\("(' + re.escape(prefix) + r'[^"\n]+)"', line))
            self.assertEqual(set(calls), set(catalog['strings']))
            self.assertIn('Resources/' + table + '.xcstrings', self.read('Questify.xcodeproj/project.pbxproj'))
        central = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertFalse(any(key.startswith(('topicReview.sources.', 'projectMerchantDraft.')) for key in central))

    def test_editor_stale_response_and_single_resolve_gates_remain(self):
        source = self.read('App/ProjectMerchantDraftController.swift')
        for token in ['context.capture() == original.target', 'source.identity == original.readerID', 'draftRevision: model.draftMutationRevision',
                      'nodeRevision: nodeRevision()', 'self.requestID == stamp', 'self.isCurrent(original)',
                      'captured.pageGeneration == pageGeneration', 'resolved.ownerMemberID == original.target.lease.session.accountID',
                      'resolved.merchantRowID == captured.merchantRowID', 'resolved.choice == captured.choice',
                      'self.cancel(original); self.context.node.wrappedValue = updated']:
            self.assertIn(token, source)
        apply = source.split('func apply(_ captured:', 1)[1].split('private static func failure', 1)[0]
        self.assertLess(apply.index('state = .resolving'), apply.index('Task {'))

if __name__ == '__main__':
    unittest.main()

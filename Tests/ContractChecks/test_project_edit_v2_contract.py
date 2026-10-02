"""Offline wiring/source evidence, not execution of the authored Swift tests."""
import os
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ProjectEditV2Contract(unittest.TestCase):
    def setUp(self):
        self.contract = (ROOT / 'Core/ProjectEditStoryContract.swift').read_text()
        self.adapter = (ROOT / 'Core/ProjectEditHTTPService.swift').read_text()
        self.builder = (ROOT / 'Core/ProjectEditContract.swift').read_text()
    def test_conditional_route_and_exact_v2_grant(self):
        for token in ['api/topic/v2/create', 'api/topic/v2/update', 'api/topic/create', 'api/topic/update', 'baseline.scope == .whitelist', 'payload["publishMode"] == .string("pro")']:
            self.assertIn(token, self.contract)
        self.assertIn('ProjectEditStoryContract.path(payload: operation.payload, baseline: operation.baseline)', self.adapter)
        self.assertIn('path: path)', self.adapter.split('approval.allows', 1)[1])
        self.assertNotIn('OperationEndpointApproval(', (ROOT / 'App/AppSession.swift').read_text())
        self.assertIn('service: ProjectEditDisabledService()', (ROOT / 'App/AppSession.swift').read_text())
    def test_schema_validation_precedes_dispatch_marker(self):
        body = self.adapter.split('public func submit(', 1)[1]
        self.assertLess(body.index('ProjectEditStoryContract.validatePayload'), body.index('dispatched.dispatchStarted = true'))
        for token in ['schemaVersion"]?.integer == 1', 'required"]?.integer == 1', 'blocks.count <= 200', 'references.count == nodes.count', '5000', '8000', '64 * 1024', 'fallbackCount == 1']:
            self.assertIn(token, self.contract)
    def test_version_readback_and_no_new_detail_endpoint(self):
        self.assertIn('"configVersion"', self.contract)
        self.assertIn('restoreMetadata(&d, body: body, topic: topic)', self.builder)
        self.assertIn('fresh.snapshot == baseline', self.adapter)
        self.assertIn('api/topic/edit-detail', self.adapter)
        self.assertNotIn('v2/edit-detail', self.adapter)
    def test_no_downgrade_or_unknown_replay(self):
        self.assertIn('isLegacyProjection', self.builder)
        self.assertIn('Set(block.keys).isSubset(of: ProjectEditStoryContract.blockFields)', self.builder)
        self.assertIn('storedBlocks = try JSONDecoder()', self.builder)
        body = self.adapter.split('public func submit(', 1)[1]
        self.assertLess(body.index('persisted.dispatchStarted == true'), body.index('approval.allows'))
        self.assertIn('return .unknown', body)
    def test_bundle_ack_is_neutral_and_separate_from_review(self):
        for field in ['topicId', 'auditTaskId', 'reviewState', 'published', 'bundledTemplateIds']:
            self.assertIn('"' + field + '"', self.contract)
        self.assertIn('ProjectEditBundleAcknowledgment.decode', self.adapter)
        self.assertIn('return .acknowledged', self.adapter)
        self.assertNotIn('case published', (ROOT / 'Core/ProjectEditService.swift').read_text())
    def test_authored_swift_coverage_is_fake_only(self):
        text = (ROOT / 'Tests/CoreTests/ProjectEditStoryContractTests.swift').read_text()
        self.assertGreaterEqual(text.count('func test'), 22)
        for token in ['StoryContractTransport: HTTPTransport', 'testLegacyGrantDoesNotAuthorizeV2', 'testConfigVersionChangeWithSameTimestamp', 'testUnsupportedReadbackFails', 'testUnknownV2CannotReplay']:
            self.assertIn(token, text)
        self.assertNotIn('URLSession', text)
    def test_current_mini_and_backend_source_when_explicitly_supplied(self):
        value = os.environ.get('CHENGYIN_CURRENT_SOURCE_ROOT')
        if value is None:
            self.skipTest('Current private source not supplied; external source parity NOT_RUN')
        source = Path(value)
        self.assertTrue(source.is_dir(), 'Explicit source root must exist')
        mini = (source / 'chengyinhub-xcx/pages/publish/fabu/index.js').read_text()
        controller = (source / 'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiTopicController.java').read_text()
        service = (source / 'chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/CmsTopicServiceImpl.java').read_text()
        compiler = (source / 'chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ChapterFlowCompiler.java').read_text()
        dto = (source / 'chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/TopicBundleSubmitResultVO.java').read_text()
        for endpoint in ['/api/topic/v2/create', '/api/topic/v2/update']:
            self.assertIn(endpoint, mini)
            self.assertIn('@PostMapping("' + endpoint.removeprefix('/api/topic') + '")', controller)
        self.assertIn("payload.publishMode === 'pro'", mini)
        self.assertIn('assertLegacyChapterFlowWritable(topicId)', service)
        self.assertIn('ChapterFlowCompiler.assertNoBlockPayload', service)
        for name in ['SCHEMA_VERSION = 1', 'MAX_BLOCKS_PER_CHAPTER = 200', 'MAX_TEXT_LENGTH = 5000', 'MAX_DESCRIPTION_LENGTH = 8000', 'MAX_SERIALIZED_BYTES = 64 * 1024']:
            self.assertIn(name, compiler)
        for field in ['topicId', 'auditTaskId', 'reviewState', 'published', 'bundledTemplateIds']:
            self.assertIn(field, dto)

if __name__ == '__main__':
    unittest.main()

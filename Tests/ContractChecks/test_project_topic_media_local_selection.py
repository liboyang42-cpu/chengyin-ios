"""Offline source-bound checks. These do not execute the authored Swift tests."""
from pathlib import Path
import re,unittest
ROOT=Path(__file__).resolve().parents[2]
def source(name):return (ROOT/name).read_text()
def code(text):return re.sub(r'//[^\n]*','',text)
def validate_contracts(c,s):
    production=code(c+s)
    for forbidden in ['URLRequest','URLSession','FileManager','PhotosUI','AVFoundation','saveLocal(', 'persistLocalChange(', 'imgUrl', 'imgArr']:
        assert forbidden not in production,forbidden
    assert 'public struct ProjectTopicMediaInspectionEvidence {' in c
    evidence=c.split('public struct ProjectTopicMediaInspectionEvidence {',1)[1].split('public struct ProjectTopicMediaLocalRecord',1)[0]
    assert 'private init(request:' in evidence and 'public init(' not in evidence and 'Codable' not in evidence
    for token in ['guard let inspector else','request.budget.begin(request.id)','try request.budget.consume(size)','hash.update(data: chunk)','try request.budget.check()','count == report.byteCount','digest == report.decodedContentSHA256','report.requestID == request.id','report.reference == request.reference','report.checks == required']:
        assert token in evidence,token
    assert 'public struct ProjectTopicMediaLocalRecord: Encodable, Equatable' in c
    assert 'private struct Wire: Decodable' in c
    assert c.index('ContentDraftJSON.parse(text)')<c.index('JSONDecoder().decode(Wire.self')
    assert 'guard original == retained' in c
    assert 'maximumRecordBytes > 0, !data.isEmpty, data.count <= maximumRecordBytes' in c
    assert 'public final class ProjectTopicMediaSelection' in s
    for token in ['context: ProjectTopicMediaContext?, policy: ProjectTopicMediaPolicy?','originalVisit == visit','current == context','currentPolicy == policy','case .unavailable = state','state == .picking(ticket)','state == .inspecting(ticket)','pair.0.request == pair.1','items != restoredRecord.items','state == .preview(preview)','state = .accepted(intent)','value.state = .needsReinspection']:
        assert token in s,token
    assert 'guard let budget else' in s and 'try budget.check()' in s
    return True

class ProjectTopicMediaLocalSelectionContracts(unittest.TestCase):
    def sources(self):return source('Core/ProjectTopicMediaContracts.swift'),source('Core/ProjectTopicMediaSelection.swift')
    def test_policy_has_no_business_defaults_or_network_authority(self):
        c,s=self.sources();self.assertTrue(validate_contracts(c,s))
        init=c.split('public init(id: UUID, revision: UInt64, maximumItems:',1)[1].split('throws',1)[0]
        self.assertNotIn('=',init)
        for name in ['maximumItems','maximumTotalBytes','maximumBytes','maximumWidth','maximumHeight','maximumPixels','maximumDurationMilliseconds','mixing']:
            self.assertIn(name,c)
        self.assertIn('policy == nil ? .unavailable(.policyUnavailable)',s)
    def test_raw_picker_metadata_and_decoded_record_cannot_be_fresh_evidence(self):
        c,s=self.sources();self.assertTrue(validate_contracts(c,s))
        signature=s.split('public func prepareInspection(',1)[1].split('->',1)[0]
        self.assertIn('[ProjectTopicMediaLocalReference]',signature);self.assertNotIn('Report',signature)
        self.assertIn('finishInspection(_ evidence: [ProjectTopicMediaInspectionEvidence]',s)
        self.assertNotRegex(code(c+s),r'\b(?:class|struct)\s+\w+\s*:\s*ProjectTopicMediaInspecting\b')
    def test_aggregate_and_per_file_limits_use_overflow_safe_subtraction(self):
        c,_=self.sources()
        for token in ['size <= maximum - count','size <= ceiling - count','item.byteCount <= maximumTotalBytes - total','item.width <= rule.maximumPixels / item.height','private let lock = NSLock()','if let failure { throw failure }','request.budget.invalidate(.byteLimit)']:
            self.assertIn(token,c)
        self.assertNotIn('item.width * item.height',c)
    def test_context_and_recovery_bind_exact_owner_without_persisting_epoch(self):
        c,s=self.sources()
        for token in ['storageNamespace.utf8.elementsEqual','sameIdentity(a.identity, b.identity)','a.draftRevision == b.draftRevision','a.visit == b.visit','a.session.epoch == b.session.epoch','a.session.viewerRevision == b.session.viewerRevision','a.session.configurationRevision == b.session.configurationRevision','editScope == .full','publishMode == "pro"']:
            self.assertIn(token,c)
        record=c.split('public struct ProjectTopicMediaLocalRecord:',1)[1];self.assertNotIn('let epoch',record)
        self.assertIn('record.matches(context)',s);self.assertIn('value.state = .needsReinspection',s)
    def test_cancel_and_context_invalidation_poison_inflight_budgets(self):
        _,s=self.sources()
        self.assertGreaterEqual(s.count('budget?.invalidate('),5)
        self.assertIn('visit = UUID(); state = .closed',s)
        self.assertIn('state = restoredRecord == nil ? .idle : .needsReinspection',s)
    def test_all_swift_cases_are_authored_and_inspector_is_explicitly_synthetic(self):
        c=source('Tests/CoreTests/ProjectTopicMediaContractsTests.swift');s=source('Tests/CoreTests/ProjectTopicMediaSelectionTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+',c)),12);self.assertEqual(len(re.findall(r'func test\w+',s)),13)
        for token in ['testByteLimitIsStickyEvenWhenInspectorSwallowsConsumerError','testAggregateInspectionBudgetStopsSecondFileAndNeverRefundsReadBytes','testDimensionAndPixelChecksAvoidOverflowAtUInt64Maximum','testUnknownNestedFieldsDuplicateEscapedKeysAndUnknownSchemaAreRejected']:
            self.assertIn(token,c)
        for token in ['testExternalABAAndSameBytesWithNewRevisionCannotReviveOldVisit','testColdMetadataRestoreRequiresSameOwnerDraftAndFreshInspectionBeforeIntent','testForeignTicketReorderedOrMissingEvidenceCannotBecomePreview','testCancelInspectionInvalidatesReadBudgetAndRejectsLateEvidence']:
            self.assertIn(token,s)
        self.assertIn('They do not decode any real',c)
    def test_documentation_distinguishes_local_constraints_from_missing_app_and_server(self):
        d=source('docs/project-topic-media-local-selection.md')
        for token in ['NOT_RUN','No production inspector','not a server capability','No image or movie file was decoded','ordinary static image','No UI methods','six new paths']:
            self.assertIn(token,d)
    def test_negative_controls_detect_evidence_and_guard_bypasses(self):
        c,s=self.sources()
        edits=[('c','private init(request:','public init(request:'),('c','request.budget.consume(size)','Void()'),
               ('c','try request.budget.check()',''),('c','hash.update(data: chunk)',''),
               ('c','count == report.byteCount','true'),('c','report.requestID == request.id','true'),
               ('c','ProjectTopicMediaLocalRecord: Encodable, Equatable','ProjectTopicMediaLocalRecord: Codable, Equatable'),
               ('s','public final class ProjectTopicMediaSelection','public struct ProjectTopicMediaSelection'),
               ('s','currentPolicy == policy','true'),('s','state == .preview(preview)','true'),
               ('s','items != restoredRecord.items','false'),('s','pair.0.request == pair.1','true')]
        for file,old,new in edits:
            left,right=(c.replace(old,new,1),s) if file=='c' else (c,s.replace(old,new,1))
            with self.subTest(old=old):
                with self.assertRaises(AssertionError):validate_contracts(left,right)

if __name__=='__main__':unittest.main()

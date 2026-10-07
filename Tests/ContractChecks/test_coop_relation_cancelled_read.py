"""Source preservation and diagnostic scope only; no Apple runtime pass is implied."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class CoopRelationCancelledReadContracts(unittest.TestCase):
    def test_cancelled_entry_precedes_invalidation_and_cleanup_owns_only_its_generation(self):
        source=(ROOT/'Core/CoopRelationDiscovery.swift').read_text().split('public func load(reader:',1)[1]
        self.assertLess(source.index('guard !Task.isCancelled else { return }'),source.index('invalidate()'))
        self.assertIn('defer { if stamp == generation { isLoading = false } }',source)
        self.assertEqual(source.count('guard !Task.isCancelled, isCurrent(), stamp == generation, reader.session == session else { return }'),2)
        self.assertIn('stamp == self.generation && isCurrent()',source)
        self.assertIn('loadedReader = identity',source)
    def test_original_hosted_predicate_wait_budget_and_failure_are_preserved(self):
        source=(ROOT/'Tests/AppUnitTests/CoopRelationPresentationOwnerTests.swift').read_text()
        self.assertIn('for _ in 0..<100',source)
        self.assertIn('try await Task.sleep(nanoseconds: 20_000_000)',source)
        self.assertIn('XCTFail(stage, file: file, line: line)\n        throw CancellationError()',source)
        self.assertIn('owner.selection == nil && !probe.childVisible && !probe.parentCovered && model.isCurrent(reader: reader)',source)
        self.assertIn('print("COOP_SYNTHETIC_OWNER " + diagnostic)',source)
        diagnostic=source.split('let diagnostic = ',1)[1].split('\n',1)[0]
        for prohibited in ['accountID','token','scope','description','name','session?.epoch']:
            self.assertNotIn(prohibited,diagnostic)
        self.assertIn('throw error',source)
    def test_new_regressions_cover_current_owner_new_generation_and_cancelled_entry(self):
        source=(ROOT/'Tests/CoreTests/CoopRelationCancellationTests.swift').read_text()
        self.assertEqual(source.count('    func test'),4)
        for token in ['task.cancel(); reader.finish(1)','current=false','old.cancel()','XCTAssertTrue(model.isLoading)','XCTAssertEqual(reader.readCount,1)','obsolete.cancel(); gate.open()']:
            self.assertIn(token,source)
if __name__=='__main__':unittest.main()

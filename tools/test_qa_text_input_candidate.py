#!/usr/bin/env python3
"""Run the QA text input slice and reproduce the unchanged truncating function.

This is not a full Core/App/runtime test. It copies the production input type,
its XCTest file, and the exact existing limitText method into an isolated Swift
package. It never modifies Package.swift, project registration or source files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import os


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift', default='swift')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = (root / 'Core/PlayKitScreenContracts.swift').read_text()
    start = source.index('    public static func limitText(')
    body = source.index('{', start)
    depth = 1
    end = body + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    original_method = source[start:end]
    (output / 'baseline-limitText.swift.txt').write_text(original_method + '\n')
    evidence = {
        'baseline_source': 'Core/PlayKitScreenContracts.swift',
        'baseline_source_sha256': hashlib.sha256((root / 'Core/PlayKitScreenContracts.swift').read_bytes()).hexdigest(),
        'original_method_sha256': hashlib.sha256(original_method.encode()).hexdigest(),
        'test_scope': 'isolated production input type plus unchanged production limitText method',
    }
    with tempfile.TemporaryDirectory(prefix='qa-text-input-') as directory:
        package = Path(directory)
        sources = package / 'Sources/QuestifyCore'; sources.mkdir(parents=True)
        tests = package / 'Tests/QuestifyCoreTests'; tests.mkdir(parents=True)
        shutil.copyfile(root / 'Core/PlayQATextInput.swift', sources / 'PlayQATextInput.swift')
        shutil.copyfile(root / 'Tests/CoreTests/PlayQATextInputTests.swift', tests / 'PlayQATextInputTests.swift')
        shutil.copyfile(root / 'Core/PlayQATextFeedbackState.swift', sources / 'PlayQATextFeedbackState.swift')
        shutil.copyfile(root / 'Tests/CoreTests/PlayQATextFeedbackStateTests.swift', tests / 'PlayQATextFeedbackStateTests.swift')
        evidence['production_sources'] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [root / 'Core/PlayQATextInput.swift', root / 'Core/PlayQATextFeedbackState.swift',
                      root / 'Tests/CoreTests/PlayQATextInputTests.swift', root / 'Tests/CoreTests/PlayQATextFeedbackStateTests.swift']}
        (sources / 'OriginalLimitText.swift').write_text('import Foundation\npublic enum OriginalPlayKitInputContract {\n' + original_method + '\n}\n')
        (tests / 'OriginalQATruncationReproductionTests.swift').write_text('''import XCTest
@testable import QuestifyCore
final class OriginalQATruncationReproductionTests: XCTestCase {
    func testUnchangedOriginalFunctionDropsAnAnswerSuffix() {
        let original = String(repeating: "a", count: 4096) + "suffix"
        let actual = OriginalPlayKitInputContract.limitText(original, toUTF16: 4096)
        XCTAssertEqual(actual.utf16.count, 4096)
        XCTAssertNotEqual(Array(actual.utf8), Array(original.utf8))
        XCTAssertFalse(actual.hasSuffix("suffix"))
        var fixed = PlayQATextInput(); fixed.mount(revision: "synthetic")
        XCTAssertTrue(fixed.update(original, current: "synthetic", mountID: fixed.mountID))
        XCTAssertEqual(Array(fixed.text(current: "synthetic", mountID: fixed.mountID).utf8), Array(original.utf8))
        XCTAssertNil(fixed.reviewInput(current: "synthetic", mountID: fixed.mountID))
    }
    func testUnchangedOriginalFunctionAlsoDropsAnOverBoundaryGrapheme() {
        let original = String(repeating: "a", count: 4095) + "😀"
        let actual = OriginalPlayKitInputContract.limitText(original, toUTF16: 4096)
        XCTAssertEqual(actual, String(repeating: "a", count: 4095))
        var fixed = PlayQATextInput(); fixed.mount(revision: "synthetic")
        XCTAssertTrue(fixed.update(original, current: "synthetic", mountID: fixed.mountID))
        XCTAssertEqual(fixed.text(current: "synthetic", mountID: fixed.mountID), original)
        XCTAssertNil(fixed.reviewInput(current: "synthetic", mountID: fixed.mountID))
    }
}
''')
        (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QATextInputCandidate", targets: [.target(name: "QuestifyCore"), .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])])
''')
        environment = os.environ.copy()
        environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'cache/clang')
        environment['SWIFTPM_MODULECACHE_OVERRIDE'] = str(package / 'cache/swift')
        command = [args.swift, 'test', '--package-path', str(package), '--cache-path', str(package / 'cache/pm'),
                   '--config-path', str(package / 'config'), '--security-path', str(package / 'security'), '--jobs', '2']
        with (output / 'tests.log').open('w') as log:
            result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
        evidence['exit_code'] = result.returncode
        (output / 'test-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps(evidence, indent=2))
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()

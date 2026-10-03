#!/usr/bin/env python3
"""Apple compile-only negative controls; never invokes a fixture or builds a new target.

Run swift test first, then supply its QuestifyCore module directory. A positive
control must typecheck before negative diagnostics count. NOT_RUN is exit 2.
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/CompileFailures/ContentDraftDispatch"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-path", type=pathlib.Path, required=True)
    args = parser.parse_args()
    swiftc = shutil.which("swiftc")
    if sys.platform != "darwin" or not swiftc:
        print("NOT_RUN: requires the approved Apple Swift compiler and previously built QuestifyCore module")
        return 2
    if not (args.module_path / "QuestifyCore.swiftmodule").exists():
        print("NOT_RUN: build QuestifyCore with testing enabled first (swift test)")
        return 2
    cases = [
        ("positive", None),
        ("raw_mutate", r"cannot convert value of type 'ContentDraftMutation'.*ContentDraftPreparedDispatch"),
        ("forge_attempt", r"(?:fileprivate.*protection level|no accessible initializers)"),
        ("forge_system_storage", r"(?:fileprivate.*protection level|no accessible initializers)"),
    ]
    with tempfile.TemporaryDirectory(prefix="content-draft-api-") as temporary:
        folder = pathlib.Path(temporary)
        for name, diagnostic in cases:
            source = folder / (name + ".swift")
            source.write_bytes((FIXTURES / (name + ".swift.fixture")).read_bytes())
            try:
                result = subprocess.run([swiftc, "-typecheck", "-I", str(args.module_path.resolve()),
                                         "-module-cache-path", str(folder / "cache"), str(source)],
                                        text=True, capture_output=True, check=False, timeout=60)
            except (OSError, subprocess.TimeoutExpired) as error:
                print("FAIL: compiler invocation for " + name + ": " + str(error))
                return 1
            output = result.stdout + result.stderr
            passed = result.returncode == 0 if diagnostic is None else result.returncode == 1 and re.search(diagnostic, output) is not None
            print(("PASS" if passed else "FAIL") + ": " + name)
            if output:
                print(output)  # retain the actual expected diagnostic in exact-SHA CI evidence
            if not passed:
                return 1
    print("SCOPE: compile-only API access checks; no fixture, storage, HTTP or UI execution")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

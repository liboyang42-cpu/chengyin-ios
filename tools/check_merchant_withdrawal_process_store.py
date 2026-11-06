#!/usr/bin/env python3
"""Offline multi-process test of the actual Swift store, not a Python reimplementation.

Requires an installed Apple Swift toolchain (Foundation/CryptoKit). Does not install
software, contact any endpoint, touch an app container, or start CI. Exit 77 means
NOT_RUN. Compiles exact production Store/Pending sources plus the unchanged protocol
and error declarations extracted from the repository. No source rewriting.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

SOURCES = ["Core/MerchantOfferWithdrawalUnifiedStore.swift",
           "Core/MerchantOfferWithdrawalOriginalPending.swift",
           "Core/CooperationFlowCoordinator.swift", "Core/CooperationFlowContracts.swift"]


def declaration(text, name):
    start = text.index(name)
    brace = text.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


DRIVER = r'''
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@main struct StoreProbe {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count == 7, let offer = Int(args[3]), let id = UUID(uuidString: args[4]) else { exit(64) }
        let store = MerchantOfferWithdrawalUnifiedStore(url: URL(fileURLWithPath: args[2]))
        let realm = args[6]
        let ready = args[5] + ".ready." + String(ProcessInfo.processInfo.processIdentifier)
        guard FileManager.default.createFile(atPath: ready, contents: Data()) else { exit(65) }
        let until = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: args[5]) {
            guard Date() < until else { exit(65) }; Thread.sleep(forTimeInterval: 0.002)
        }
        do {
            let p = try MerchantOfferWithdrawalOriginalPending(accountID: 1, merchantID: 2, offerID: offer,
                namespace: "process-fixture", realm: realm, requestID: id,
                intentSHA256: String(repeating: "a", count: 64), reasonSHA256: String(repeating: "b", count: 64),
                expectedSHA256: String(repeating: "c", count: 64))
            let key = "endpoint:" + Data(realm.utf8).base64EncodedString() + ":1:offer-\(offer)"
            for _ in 0..<2000 {
                do {
                    switch args[1] {
                    case "begin": try store.begin(p); print("ACQUIRED")
                    case "legacy": try store.acquire(key); print("ACQUIRED")
                    case "complete": try store.complete(key); print("COMPLETED")
                    case "ack": try store.acknowledge(p); print("ACKNOWLEDGED")
                    case "read":
                        let entries = try store.entries(account: 1, merchant: 2, namespace: "process-fixture", realm: realm)
                        print(String(data: try JSONEncoder().encode(entries), encoding: .utf8)!)
                    default: exit(64)
                    }
                    return
                } catch CoopFlowFailure.storage {
                    // Bounded test-only retry of a contended nonblocking lock. No HTTP or
                    // business action exists here. Persistent storage faults still fail.
                    Thread.sleep(forTimeInterval: 0.005)
                } catch CoopFlowFailure.ambiguous { print("CONFLICT"); return }
            }
            fputs("Persistent storage failure or lock contention\n", stderr); exit(66)
        } catch { fputs("\(error)\n", stderr); exit(67) }
    }
}
'''


def run(repo):
    hashes = {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in SOURCES}
    compiler = shutil.which("swiftc")
    if compiler is None:
        print(json.dumps({"status": "NOT_RUN", "reason": "swiftc is not installed", "source_sha256": hashes}, indent=2))
        return 77
    with tempfile.TemporaryDirectory(prefix="merchant-withdrawal-process-") as temporary:
        work = Path(temporary).resolve()
        bridge = work / "Contracts.swift"
        bridge.write_text("import Foundation\n" + declaration((repo / SOURCES[2]).read_text(), "@MainActor public protocol CoopFlowLockStore")
                          + "\n" + declaration((repo / SOURCES[3]).read_text(), "public enum CoopFlowFailure") + "\n")
        driver = work / "Driver.swift"
        driver.write_text(DRIVER)
        binary = work / "probe"
        command = [compiler, "-swift-version", "5", "-parse-as-library", str(repo / SOURCES[0]), str(repo / SOURCES[1]),
                   str(bridge), str(driver), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        if compiled.returncode:
            print(json.dumps({"status": "COMPILE_FAILED", "source_sha256": hashes, "stderr": compiled.stderr}, indent=2))
            return 1
        realm = "https://process-fixture.invalid/"
        gate = work / "start"
        gate.touch()

        def args(path, operation="begin", offer=3, request=None):
            return [str(binary), operation, str(path), str(offer), request or str(uuid.uuid4()), str(gate), realm]

        def once(path, operation="begin", offer=3, request=None):
            result = subprocess.run(args(path, operation, offer, request), capture_output=True, text=True, timeout=20)
            assert result.returncode == 0, result.stderr
            return result.stdout.strip()

        def race(commands):
            gate.unlink()
            for ready in work.glob("start.ready.*"):
                ready.unlink()
            children = [subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for command in commands]
            try:
                deadline = time.monotonic() + 10
                while not all((work / f"start.ready.{child.pid}").exists() for child in children):
                    assert time.monotonic() < deadline, "Processes did not reach the start barrier"
                    assert all(child.poll() is None for child in children), "A process exited before the start barrier"
                    time.sleep(0.005)
                gate.touch()
                results = []
                for child in children:
                    stdout, stderr = child.communicate(timeout=20)
                    assert child.returncode == 0, stderr
                    results.append(stdout.strip())
                return results
            finally:
                for child in children:
                    if child.poll() is None:
                        child.kill(); child.wait()

        passed = []
        path = work / "same" / "locks.json"
        results = race([args(path) for _ in range(12)])
        assert results.count("ACQUIRED") == 1 and results.count("CONFLICT") == 11, results
        assert len(json.loads(once(path, "read"))) == 1
        passed.append("12 processes, one resource: exactly one durable original")

        path = work / "different" / "locks.json"
        results = race([args(path, offer=i) for i in range(1, 13)])
        assert results == ["ACQUIRED"] * 12, results
        assert {p["offerID"] for p in json.loads(once(path, "read"))} == set(range(1, 13))
        passed.append("12 processes, different resources: no lost pending records")

        path = work / "mixed" / "locks.json"
        results = race([args(path, "begin"), args(path, "legacy")])
        assert sorted(results) == ["ACQUIRED", "CONFLICT"], results
        passed.append("legacy and original acquisition share one lock domain")

        path = work / "ack" / "locks.json"
        old, new = str(uuid.uuid4()), str(uuid.uuid4())
        assert once(path, request=old) == "ACQUIRED"
        assert once(path, "complete") == "CONFLICT"
        assert once(path, "ack", request=new) == "CONFLICT"
        assert json.loads(once(path, "read"))[0]["requestID"].lower() == old
        passed.append("legacy completion and wrong UUID cannot erase an original")
        results = race([args(path, "ack", request=old), args(path, request=new)])
        assert results[0] == "ACKNOWLEDGED" and results[1] in {"ACQUIRED", "CONFLICT"}, results
        records = json.loads(once(path, "read"))
        assert [p["requestID"].lower() for p in records] == ([new] if results[1] == "ACQUIRED" else []), records
        passed.append("acknowledge/begin race leaves only the matching successor or no record")
        print(json.dumps({"status": "PASSED", "scope": "cooperating processes using this exact store only",
                          "source_sha256": hashes, "cases": passed,
                          "not_proven": ["old binaries that ignore flock", "crashes at each fsync/rename step",
                                         "Darwin device data-protection lifecycle", "server transactions or HTTP"]}, indent=2))
        return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    options = parser.parse_args()
    raise SystemExit(run(options.repo.resolve()))

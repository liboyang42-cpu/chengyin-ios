#!/usr/bin/env python3
"""Build a focused Linux test package; never modifies product sources or calls a service.

Apple-only webhook metadata is an unexercised fail-closed stand-in. Unrelated
large source files contribute exact top-level declarations. Test signatures gain
async for Linux XCTest discovery; assertions and method bodies stay unchanged.
This is isolated test evidence, not an iOS build or a live journey acceptance.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

FULL_SOURCES = ['APIConfiguration.swift', 'Account.swift', 'AccountComplianceContracts.swift', 'ActivityDetail.swift', 'ActivityPeople.swift', 'ActivityReviews.swift', 'ActivitySummary.swift', 'AppPreferences.swift', 'AuthRequestBuilder.swift', 'AuthService.swift', 'OperationAdapterSafety.swift', 'ProfileContracts.swift', 'ProfileReading.swift', 'ProfileService.swift', 'PublisherAuthoritySource.swift', 'RegionalConfiguration.swift', 'RegistrationConfirmedReadback.swift', 'RegistrationContracts.swift', 'RegistrationCoordinator.swift', 'RegistrationProduction.swift', 'RegistrationService.swift', 'RegistrationUIFlow.swift', 'RegistrationUIForm.swift', 'RegistrationWaitlist.swift']
DECLARATIONS = [
    ("ProjectEditDraft.swift", "ProjectEditJSON"),
    ("ProfileOrderTimeline.swift", "ProfileOrderDetailFacts"),
    ("ProfileOrderHistoryFilter.swift", "ProfileOrderHistoryFacts"),
    ("SocialAccountReading.swift", "SocialAccountIdentity"),
    ("SearchMapActivityPresentation.swift", "SearchMapActivityTime"),
    ("PublisherLifecycleContracts.swift", "PublisherLifecycleError"),
]
TESTS = ["RegistrationProductionTests", "RegistrationServiceTests", "RegistrationCoordinatorTests",
         "RegistrationUIFlowTests", "RegistrationWaitlistFlowTests", "RegistrationContractTests"]

def digest(value):
    return hashlib.sha256(value).hexdigest()

def declaration(source, name):
    match = re.search(r"^(?:@MainActor )?public (?:struct|enum|class|protocol) " + name + r"\b", source, re.M)
    if match is None:
        raise ValueError("Missing declaration: " + name)
    begin = source.index("{", match.start())
    depth, end = 1, begin + 1
    # The selected declarations contain balanced literal braces. Fail compilation
    # if future source changes invalidate this narrowly scoped extraction.
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return "import Foundation\n" + source[match.start():end] + "\n"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / "Core").mkdir()
    (out / "Tests").mkdir()
    manifest = {"evidence": "isolated Linux only", "sources": {}, "extracted": {}, "tests": {}, "async_signature_adaptations": 0}
    for name in FULL_SOURCES:
        data = (root / "Core" / name).read_bytes()
        (out / "Core" / name).write_bytes(data)
        manifest["sources"]["Core/" + name] = digest(data)
    for filename, name in DECLARATIONS:
        data = (root / "Core" / filename).read_bytes()
        extracted = declaration(data.decode(), name).encode()
        (out / "Core" / (name + "Extract.swift")).write_bytes(extracted)
        manifest["extracted"][name] = {"path": "Core/" + filename, "source_sha256": digest(data), "slice_sha256": digest(extracted)}
    for name in TESTS:
        path = "Tests/CoreTests/" + name + ".swift"
        data = (root / path).read_bytes()
        value, count = re.subn(r"(func test\w+\([^\n]*?\))(?= throws| \{)", r"\1 async", data.decode())
        (out / "Tests" / (name + ".swift")).write_text(value)
        manifest["tests"][path] = {"original_sha256": digest(data), "harness_sha256": digest(value.encode())}
        manifest["async_signature_adaptations"] += count
    (out / "Core" / "UnexercisedWebhookType.swift").write_text("""import Foundation
// Harness only: registration never uses webhook metadata. Refuse accidental coding.
public struct NativeWebhookPendingMetadata: Codable, Equatable {
    public init(from decoder: Decoder) throws { throw APIError.notConfigured }
    public func encode(to encoder: Encoder) throws { throw APIError.notConfigured }
}
""")
    (out / "Package.swift").write_text("""// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QuestifyCore", products: [.library(name: "QuestifyCore", targets: ["QuestifyCore"])], targets: [.target(name: "QuestifyCore", path: "Core"), .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"], path: "Tests")])
""")
    (out / "source-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("Prepared", out, "with", len(FULL_SOURCES), "complete sources and", len(DECLARATIONS), "exact declarations")

if __name__ == "__main__":
    main()

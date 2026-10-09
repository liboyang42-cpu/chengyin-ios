"""Fail-closed inverse for exactly two approved CI138 UI52 driver additions.

Standalone validation is for this isolated candidate. The unified current-source
planning layer must validate the combined inventory, then compose this byte
inverse with other reviewed inverses before invoking unchanged historical guards.
No old runner, profile, workflow, source hash or timing floor is rewritten here.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = "Tests/ContractChecks/fixtures/run138_ui52_driver.json"
CONTRACT_SHA256 = "a0cbac7ca82b97e94745b46fbb1e5fe1157d6a0b85c2eee5f046b7d243270cb8"
MARKETING = "Tests/AppUITests/MerchantMarketingUITests.swift"
STORY = "Tests/AppUITests/ProjectStoryImageFlowTests.swift"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def contract(root=ROOT):
    raw = (Path(root) / CONTRACT_PATH).read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError("Unreviewed UI52 source/cost contract")
    result = json.loads(raw)
    if set(result["files"]) != {MARKETING, STORY}:
        raise ValueError("Unapproved UI52 source scope")
    return result


def original_source(relative, raw, root=ROOT):
    """Restore only a known exact postimage to its exact published preimage."""
    row = contract(root)["files"].get(relative)
    if row is None:
        raise ValueError("No approved UI52 inverse for " + relative)
    if digest(raw) != row["after_sha256"]:
        raise ValueError("Changed or unknown current UI52 source: " + relative)
    source = raw.decode("utf-8")
    for hunk in reversed(row["hunks"]):
        if source.count(hunk["after"]) != 1:
            raise ValueError("Missing or repeated exact UI52 span")
        source = source.replace(hunk["after"], hunk["before"], 1)
    restored = source.encode("utf-8")
    if digest(restored) != row["before_sha256"]:
        raise ValueError("UI52 source did not restore exactly")
    return restored


def validate_costs(root=ROOT):
    costs = contract(root)["method_costs"]
    expected = {
        "MerchantMarketingUITests.testNormalMerchantWorkbenchOpensDormantMarketingInBothLanguages":
            (114.954, 6, 30, 144.954),
        "ProjectStoryImageFlowTests.testChosenStoryImageAppliesOnlyAfterUploadAndRestoresIntoExactPreparedOrder":
            (900, 1, 5, 905),
    }
    if set(costs) != set(expected):
        raise ValueError("Unapproved UI52 complete-method identity")
    for method, (prior, executions, added, current) in expected.items():
        row = costs[method]
        if (row["measured"] is not False or row["added_wait_seconds"] != 5
                or row["executions"] != executions
                or row["prior_complete_method_seconds"] != prior
                or row["added_seconds"] != added
                or row["candidate_complete_method_seconds"] != current
                or row["added_wait_seconds"] * row["executions"] != added
                or prior + added != current):
            raise ValueError("Changed UI52 full-method allowance")
    if not costs[next(key for key in costs if key.startswith("ProjectStoryImageFlowTests."))][
            "requires_explicit_over_900_review"]:
        raise ValueError("The exact-current 905-second exception must stay explicit")
    return costs


def validate_current(root=ROOT):
    """Validate isolated candidate, without claiming combined or active-CI success."""
    root = Path(root)
    if (root / "Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift").exists():
        try:
            from run138_current_source_projection import validate_ui52_component
        except ModuleNotFoundError:
            from tools.run138_current_source_projection import validate_ui52_component
        return validate_ui52_component(root)
    c = contract(root)
    actual = sorted(str(p.relative_to(root)) for p in (root / "Tests/AppUITests").glob("*.swift"))
    if actual != c["original_inventory"]:
        raise ValueError("UI52 changed the original UI file inventory")
    for relative, row in c["files"].items():
        original_source(relative, (root / relative).read_bytes(), root)
    for relative, expected in c["protected_sha256"].items():
        if digest((root / relative).read_bytes()) != expected:
            raise ValueError("Protected original UI/helper/profile/guard/workflow changed: " + relative)
    costs = validate_costs(root)
    return {
        "status": "isolated_exact_source_validated_not_runtime_tested",
        "base_tree": c["base_tree"],
        "changed_ui_paths": sorted(c["files"]),
        "new_wait_allowance_seconds": sum(row["added_seconds"] for row in costs.values()),
        "method_costs": costs,
        "active_historical_guards_still_require_unified_current_source_layer": True,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    print(json.dumps(validate_current(args.root), indent=2))


"""Offline guards for the reviewed two-digest/two-path Gitleaks exception.

These tests validate the live config and source evidence without network access or
installing a scanner. The separately recorded real Gitleaks 8.24.3 controls remain
the scanner-level evidence; the local predicate below is only a scope guard.
"""
from copy import deepcopy
from pathlib import Path
import ast
import hashlib
import json
import re
import unittest
import tomllib

ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATHS = (
    "Tests/AppUITests/WeChatAppAuthFlowTests.swift",
    "Tests/ContractChecks/test_merchant_business_access_lifetime.py",
)
# Keep source names and digest literals in separate structures: source names can
# contain scanner keywords even though these values are source-integrity hashes.
REVIEWED_DIGESTS = (
    "d5c4b559ba35a52da62527695761a638bb8dfe512f45f73d0010cfa63a1b7942",
    "8dc268db59480c9718286193dcdf2b5674121dc91e3104fbf46217515d14e2b0",
)
TOOL_PATHS = (
    "tools/club_customer_directory_admission.py",
    "tools/targeted_native_selection.json",
)
EXPECTED_PATH_REGEXES = [
    r"^tools/club_customer_directory_admission\.py$",
    r"^tools/targeted_native_selection\.json$",
]
EXPECTED_DIGEST_REGEXES = ["^" + value + "$" for value in REVIEWED_DIGESTS]


def _require(condition):
    if not condition:
        raise AssertionError("Configuration exceeds the reviewed exact scope")


def _validate_reviewed_config(config):
    """Fail closed on any matching or exclusion change beyond the reviewed one."""
    _require(set(config) == {"title", "extend", "rules"})
    _require(isinstance(config["title"], str) and config["title"])
    _require(config["extend"] == {"useDefault": True})
    _require(isinstance(config["rules"], list) and len(config["rules"]) == 1)
    rule = config["rules"][0]
    _require(set(rule) == {"id", "allowlists"})
    _require(rule["id"] == "generic-api-key")
    _require(isinstance(rule["allowlists"], list) and len(rule["allowlists"]) == 1)
    allow = rule["allowlists"][0]
    _require(set(allow) == {"description", "condition", "regexTarget", "paths", "regexes"})
    _require(isinstance(allow["description"], str) and allow["description"])
    _require(allow["condition"] == "AND")
    _require(allow["regexTarget"] == "secret")
    _require(allow["paths"] == EXPECTED_PATH_REGEXES)
    _require(allow["regexes"] == EXPECTED_DIGEST_REGEXES)
    return allow


def _exception_applies(config, rule_id, path, extracted_value):
    """Scope predicate for the already validated, exact anchored configuration.

fullmatch avoids Python '$' accepting a final newline; Go's configured '$' is
end-of-text. This helper models this one exception, not Gitleaks detection.
"""
    allow = _validate_reviewed_config(config)
    return (rule_id == "generic-api-key"
            and any(re.fullmatch(pattern, path) for pattern in allow["paths"])
            and any(re.fullmatch(pattern, extracted_value) for pattern in allow["regexes"]))


def _embedded_digest_maps(text):
    mappings = []
    for line in text.splitlines():
        if line.startswith("_CLUB_E2B_SHA256 = "):
            statement = ast.parse(line).body[0]
            mappings.append(ast.literal_eval(statement.value))
    return mappings


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


class GitleaksExactSourceDigestTests(unittest.TestCase):
    def setUp(self):
        self.config = tomllib.loads((ROOT / ".gitleaks.toml").read_text())

    def test_all_default_rules_are_retained_without_detection_overrides(self):
        _validate_reviewed_config(self.config)

    def test_reviewed_values_are_recomputed_from_actual_source_bytes(self):
        for relative, reviewed in zip(SOURCE_PATHS, REVIEWED_DIGESTS):
            with self.subTest(source=relative):
                self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), reviewed)

    def test_both_allowed_tool_files_bind_values_to_the_reviewed_source_paths(self):
        helper = (ROOT / TOOL_PATHS[0]).read_text()
        selection = json.loads((ROOT / TOOL_PATHS[1]).read_text())
        helper_maps = _embedded_digest_maps(helper)
        selection_maps = [mapping for value in _strings(selection)
                          for mapping in _embedded_digest_maps(value)]
        for maps in (helper_maps, selection_maps):
            self.assertEqual(len(maps), 1)
            for relative, reviewed in zip(SOURCE_PATHS, REVIEWED_DIGESTS):
                with self.subTest(source=relative):
                    self.assertEqual(maps[0][relative], reviewed)

    def test_only_the_four_exact_digest_path_combinations_are_allowed(self):
        for relative in TOOL_PATHS:
            for reviewed in REVIEWED_DIGESTS:
                with self.subTest(path=relative, digest=reviewed):
                    self.assertTrue(_exception_applies(self.config, "generic-api-key", relative, reviewed))

    def test_same_path_different_values_are_never_covered(self):
        different = [hashlib.sha256(b"synthetic negative control, not a credential").hexdigest()]
        for reviewed in REVIEWED_DIGESTS:
            different.extend(("0" + reviewed, reviewed + "0", reviewed.upper(), reviewed + "\n",
                              ("0" if reviewed[0] != "0" else "1") + reviewed[1:]))
        for relative in TOOL_PATHS:
            for value in different:
                with self.subTest(path=relative, value=value):
                    self.assertFalse(_exception_applies(self.config, "generic-api-key", relative, value))

    def test_same_digest_other_paths_are_never_covered(self):
        different = ["tools/unreviewed_digests.txt"]
        for relative in TOOL_PATHS:
            different.extend(("shadow/" + relative, relative + ".bak", "/" + relative,
                              "./" + relative, relative.upper(), relative + "\n"))
        for relative in different:
            for reviewed in REVIEWED_DIGESTS:
                with self.subTest(path=relative, digest=reviewed):
                    self.assertFalse(_exception_applies(self.config, "generic-api-key", relative, reviewed))

    def test_other_rules_are_never_covered_even_at_exact_digest_paths(self):
        for other_rule in ("github-pat", "aws-access-token", "unrelated-rule"):
            for relative in TOOL_PATHS:
                for reviewed in REVIEWED_DIGESTS:
                    with self.subTest(rule=other_rule, path=relative):
                        self.assertFalse(_exception_applies(self.config, other_rule, relative, reviewed))

    def test_full_match_or_line_content_is_not_an_allowed_secret(self):
        for relative in TOOL_PATHS:
            for reviewed in REVIEWED_DIGESTS:
                value = 'api_key = "' + reviewed + '"; auth_token = "different_value"'
                self.assertFalse(_exception_applies(self.config, "generic-api-key", relative, value))

    def test_config_mutations_cannot_broaden_scope_or_disable_defaults(self):
        mutations = []
        def changed():
            config = deepcopy(self.config)
            mutations.append(config)
            return config
        changed()["extend"]["useDefault"] = False
        changed()["extend"]["disabledRules"] = ["github-pat"]
        changed()["allowlist"] = {"paths": [".*"]}
        changed()["rules"].append({"id": "unrelated-rule", "regex": ".*"})
        changed()["rules"][0]["regex"] = ".*"
        changed()["rules"][0]["id"] = "github-pat"
        changed()["rules"][0]["allowlists"].append({"paths": [".*"]})
        for key, value in (
                ("condition", "OR"), ("regexTarget", "line"), ("regexTarget", "match"),
                ("paths", [".*"]), ("regexes", [r"^[a-f0-9]{64}$"]),
                ("paths", EXPECTED_PATH_REGEXES + [r"^tools/other\.py$"]),
                ("regexes", EXPECTED_DIGEST_REGEXES + ["^unreviewed$"]),
                ("commits", ["0" * 40]), ("stopwords", ["client"])):
            changed()["rules"][0]["allowlists"][0][key] = value
        for config in mutations:
            with self.subTest(config=config), self.assertRaises(AssertionError):
                _validate_reviewed_config(config)


if __name__ == "__main__":
    unittest.main()

import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import check_signing_evidence as tool  # noqa: E402

VALID = """CODE_SIGNING_ALLOWED = YES
DEVELOPMENT_TEAM = 9A8B7C6D5E
PRODUCT_BUNDLE_IDENTIFIER = com.chengyin.questify
QUESTIFY_API_BASE_URL = https:/$()/api.chengyinhub.cn/v1
QUESTIFY_SESSION_REALM = cn-prod
"""


class SigningEvidenceContract(unittest.TestCase):
    def test_swift_symbols_present(self):
        src = (ROOT / "Core/ProductionSigningAndLocalXcconfigValidatorContract.swift").read_text()
        for s in ("validateReleaseEvidence", "parseBuildSettings", "ProductionSigningEvidenceResult"):
            self.assertIn(s, src)
        tests = (ROOT / "Tests/CoreTests/ProductionSigningAndLocalXcconfigValidatorContractTests.swift").read_text()
        self.assertIn("testEachInvalidCoordinateIsRejected", tests)

    def test_repository_defaults_stay_placeholder_safe(self):
        base = (ROOT / "Config/Base.xcconfig").read_text()
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = invalid.example.questify.ios", base)
        self.assertRegex(base, r"(?m)^QUESTIFY_API_BASE_URL =\s*$")
        self.assertRegex(base, r"(?m)^QUESTIFY_SESSION_REALM =\s*$")
        self.assertNotRegex(base, r"(?m)^DEVELOPMENT_TEAM\s*=\s*\S")

    def test_repository_base_is_rejected_as_evidence(self):
        self.assertTrue(tool.validate(tool.parse((ROOT / "Config/Base.xcconfig").read_text())))
        self.assertTrue(tool.validate({}))

    def test_valid_and_each_invalid(self):
        good = tool.parse(VALID)
        self.assertEqual(tool.validate(good), [])
        for k, v in [("CODE_SIGNING_ALLOWED", "NO"), ("DEVELOPMENT_TEAM", ""),
                     ("PRODUCT_BUNDLE_IDENTIFIER", "invalid.example.questify.ios"),
                     ("QUESTIFY_API_BASE_URL", ""), ("QUESTIFY_API_BASE_URL", "https://47.103.124.64/x"),
                     ("QUESTIFY_SESSION_REALM", "")]:
            bad = dict(good, **{k: v})
            self.assertTrue(tool.validate(bad), (k, v))

    def test_cli_exit_codes(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt") as f:
            f.write(VALID.replace("YES", "NO"))
            f.flush()
            r = subprocess.run([sys.executable, str(ROOT / "tools/check_signing_evidence.py"), f.name])
            self.assertEqual(r.returncode, 1)

    def test_no_new_endpoint_strings_in_tool(self):
        src = (ROOT / "tools/check_signing_evidence.py").read_text()
        self.assertNotIn("http://", src)
        self.assertNotIn("xcodebuild\"", src)


if __name__ == "__main__":
    unittest.main()

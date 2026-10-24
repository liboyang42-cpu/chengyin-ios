"""Source contract for the C10 platform launch issuer. Does not compile Swift.

XCTest / App / CI = NOT_RUN. Coverage is not 100%.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
ISSUER = ROOT / "Core/H5LaunchIssuer.swift"
PRODUCER = ROOT / "Core/H5LaunchProducer.swift"
PARENT = ROOT / "Core/H5ShellParentFlow.swift"
RECOVER = ROOT / "Core/WorkshopInstallRecoverEntry.swift"
SHELL_VIEW = ROOT / "App/H5PlatformShellView.swift"
SHELL_LOAD = ROOT / "Core/H5ShellLoad.swift"
SESSION = ROOT / "App/AppSession.swift"
ROOT_COMPOSITION = ROOT / "App/AppCompositionRoot.swift"
PBX = ROOT / "Questify.xcodeproj/project.pbxproj"


def struct_body(text, name, end_marker):
    start = text.index(f"struct {name}")
    end = text.index(end_marker, start)
    return text[start:end]


class C10LaunchIssuerContract(unittest.TestCase):
    def test_platform_issues_the_held_https_host_and_a_new_nonce(self):
        text = ISSUER.read_text()
        license = struct_body(text, "LicenseInstall", "struct AuthorSubmission")
        author = struct_body(text, "AuthorSubmission", "private struct IssuedOrigin")
        for record in (license, author):
            self.assertNotIn("parentOrigin", record)
            self.assertNotIn("nonce", record)
            self.assertNotIn("shellURL", record)
        self.assertIn("APIConfiguration", text)
        self.assertIn("configuration?.baseURL", text)
        self.assertIn("baseURL.scheme == \"https\"", text)
        self.assertIn("UUID().uuidString", text)
        self.assertIn("H5LaunchDescription(parentOrigin:", text)
        self.assertIn("mainToken: nil", text)
        self.assertIn("https://\\(name)", text)
        self.assertIn("H5ShellParentFlow.loadRequest", text)
        self.assertIn("nonce=\\(encoded)", text)
        self.assertIn("parent.open", text)
        self.assertIn("parent.readOriginalReceipt", text)
        self.assertIn("entry.recover", text)
        self.assertIn("advanced/start", text)
        self.assertIn("native-context", text)
        self.assertNotIn("owned.launch", text)
        self.assertNotIn("author.launch", text)
        self.assertNotIn("EntryLaunch", text)
        self.assertNotIn("startAdvanced", text)
        self.assertNotIn("nativeContext(", text)
        self.assertNotIn("SecCertificate", text)
        self.assertNotIn(".zip", text)
        self.assertNotIn("chengyin.com", text)
        self.assertNotIn("example.com", text)
        self.assertNotIn("LinearGradient", text)
        self.assertNotIn("systemName", text)
        self.assertNotIn("struct H5LaunchProducer", text)
        self.assertNotIn("struct H5PlatformShellView", text)
        self.assertNotIn("enum H5ShellLoad", text)
        self.assertNotIn("struct WorkshopInstallRecoverEntry", text)
        self.assertNotIn("struct AppSession", text)
        self.assertNotIn("AppCompositionRoot", text)
        self.assertTrue(PRODUCER.is_file())
        self.assertTrue(PARENT.is_file())
        self.assertTrue(RECOVER.is_file())
        self.assertNotIn("struct H5LaunchIssuer", PRODUCER.read_text())
        self.assertNotIn("H5LaunchIssuer.swift", PBX.read_text())
        self.assertTrue(SESSION.is_file())
        self.assertTrue(ROOT_COMPOSITION.is_file())
        self.assertFalse(SHELL_VIEW.exists())
        self.assertFalse(SHELL_LOAD.exists())


if __name__ == "__main__":
    unittest.main()

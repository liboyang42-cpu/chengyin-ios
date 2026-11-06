"""Source contract for the C10 launch producer. Does not compile Swift.

XCTest / App / CI = NOT_RUN. Coverage is not 100%.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PRODUCER = ROOT / "Core/H5LaunchProducer.swift"
VIEW = ROOT / "App/H5LaunchProducerView.swift"
PARENT = ROOT / "Core/H5ShellParentFlow.swift"
SHELL_VIEW = ROOT / "App/H5PlatformShellView.swift"
SHELL_LOAD = ROOT / "Core/H5ShellLoad.swift"
RECOVER = ROOT / "Core/WorkshopInstallRecoverEntry.swift"


class C10LaunchProducerContract(unittest.TestCase):
    def test_producer_posts_nonce_only_through_the_existing_parent(self):
        text = PRODUCER.read_text()
        self.assertIn("H5ShellParentFlow.loadRequest", text)
        self.assertIn("nonce=\\(encoded)", text)
        self.assertIn("parent.open", text)
        self.assertIn("parent.readOriginalReceipt", text)
        self.assertIn("entry.recover", text)
        self.assertNotIn("https://", text)
        self.assertNotIn("startAdvanced", text)
        self.assertNotIn("nativeContext(", text)
        self.assertIn("advanced/start", text)
        self.assertIn("native-context", text)
        self.assertNotIn("struct H5PlatformShellView", text)
        self.assertNotIn("enum H5ShellLoad", text)
        self.assertNotIn("struct WorkshopInstallRecoverEntry", text)
        self.assertNotIn("LinearGradient", text)
        view = VIEW.read_text()
        self.assertIn("H5ShellParentFlowView", view)
        self.assertIn("h5.launchTicket", view)
        self.assertNotIn("LinearGradient", view)
        self.assertNotIn("systemName", view)
        self.assertNotIn("https://", view)
        self.assertTrue(PARENT.is_file())
        self.assertTrue(RECOVER.is_file())
        self.assertFalse(SHELL_VIEW.exists())
        self.assertFalse(SHELL_LOAD.exists())


if __name__ == "__main__":
    unittest.main()

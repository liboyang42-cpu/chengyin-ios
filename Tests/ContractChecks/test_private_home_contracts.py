"""Discover the private-home source guards in the existing hosted contract job."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("private_home_source_guard", ROOT / "tools/check_private_home.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def load_tests(loader, tests, pattern):
    return loader.loadTestsFromTestCase(module.PrivateHomeSourceTests)

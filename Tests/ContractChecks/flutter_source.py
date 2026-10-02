"""Optional external-source comparisons, separate from native-local contracts."""
import os
import pathlib

DEFAULT_SOURCE_ROOT = pathlib.Path(__file__).resolve().parents[3] / 'app-audit'
SOURCE_ROOT_ENV = 'CHENGYIN_FLUTTER_SOURCE_ROOT'


def read_flutter_source(test_case, relative_path):
    """Skip only an absent optional checkout; broken/provided checkouts must fail."""
    configured = os.environ.get(SOURCE_ROOT_ENV)
    root = pathlib.Path(configured) if configured else DEFAULT_SOURCE_ROOT
    if not root.exists() and not configured:
        test_case.skipTest(
            'External Flutter parity NOT_RUN: ../app-audit is unavailable; '
            'native-local assertions run separately')
    # A present root with a missing/malformed file is an error, never a skip.
    return (root / 'lib' / relative_path).read_text()

"""One fresh raw-byte admission per complete run109 historical source batch."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = 'tools/tests/run109_amendment_budget_history.py'
BEFORE_SHA256 = '8df070958178a8c613aefc027e4678ed212f8ce9a5424491382dc82748cbfde8'
BATCH_PREFIX = """    if Path(directory).resolve() == (ROOT / 'Tests/AppUITests').resolve():
        from tools.tests.player_map_history_budget_history import validated_pre_run129_directory
        with validated_pre_run129_directory(ROOT) as current:
            return historical_ui_sources(current)
"""

PROBE = r'''
from contextlib import contextmanager, ExitStack
import hashlib, json, os, tempfile, types
from pathlib import Path
from unittest.mock import patch
from tools import run138_current_source_projection as entry
from tools import run138_editor_readiness as current
from tools.tests import run109_amendment_budget_history as history
from tools.tests import player_map_history_budget_history as batches
ROOT = Path.cwd(); UI = ROOT / 'Tests/AppUITests'
EXPECTED = [Path(name).stem for name in history.source_index()['baseline_ui_filenames']
            if Path(name).stem not in history.MOVED_CLASSES]
@contextmanager
def change(path, kind):
    old = path.read_bytes() if path.exists() else None
    stamp = path.stat() if path.exists() else None
    try:
        if kind == 'delete': path.unlink()
        elif kind == 'add': path.write_bytes(b'// Unreviewed input.\n')
        elif kind == 'same_size_mtime':
            path.write_bytes(bytes([old[0] ^ 1]) + old[1:])
            os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            assert path.stat().st_size == stamp.st_size
            assert path.stat().st_mtime_ns == stamp.st_mtime_ns
        elif kind == 'crlf':
            assert b'\n' in old
            path.write_bytes(old.replace(b'\n', b'\r\n'))
        else: raise AssertionError(kind)
        yield
    finally:
        if old is None:
            if path.exists(): path.unlink()
        else:
            path.write_bytes(old)
            os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
def reject(action, message=None, errors=(ValueError, AssertionError, OSError)):
    try: action()
    except errors as error:
        if message is not None: assert message in str(error), str(error)
        return
    raise AssertionError('Changed input returned a historical batch')
def call(): return history.historical_ui_sources(UI)
def output(paths): return [(path.name, path.read_bytes()) for path in paths]
report = {'mode': MODE}
if MODE == 'positive':
    helper = ROOT / HELPER; text = helper.read_text()
    assert text.count(BATCH_PREFIX) == 1
    before = text.replace(BATCH_PREFIX, '', 1)
    assert hashlib.sha256(before.encode()).hexdigest() == BEFORE_SHA256
    original = types.ModuleType('run109_exact_predecessor')
    original.__file__ = str(helper)
    exec(compile(before, str(helper), 'exec'), original.__dict__)
    old = output(original.historical_ui_sources(UI))
    with patch.object(current, 'validate_current', wraps=current.validate_current) as admitted, \
            patch.object(entry, 'previous_directory', wraps=entry.previous_directory) as previous, \
            patch.object(history, 'historical_ui_source', wraps=history.historical_ui_source) as reader:
        first = call(); second = call()
        assert first is not second
        assert admitted.call_count == previous.call_count == 2, (admitted.call_count, previous.call_count)
        assert reader.call_count == 2 * len(EXPECTED), reader.call_count
        assert [args.args[1] for args in reader.call_args_list] == EXPECTED * 2
        assert output(first) == output(second) == old
    first.clear()
    assert output(second) == old
    rows = [(name, hashlib.sha256(raw).hexdigest(), len(raw)) for name, raw in old]
    report.update(source_count=len(rows), admissions_per_top_level=1,
                  complete_output_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest())
elif MODE in ('current', 'cached'):
    cached = entry.previous_directory(UI)
    directory = UI if MODE == 'current' else cached
    for kind in ('same_size_mtime', 'crlf', 'delete', 'add'):
        file = directory / ('Unreviewed.swift' if kind == 'add' else 'TicketWalletFlowTests.swift')
        with change(file, kind): reject(call)
    file = directory / 'TicketWalletFlowTests.swift'; read = Path.read_bytes
    def denied(path):
        if path == file: raise PermissionError('sentinel denied raw read')
        return read(path)
    with patch.object(Path, 'read_bytes', denied): reject(call, 'sentinel denied raw read')
    if MODE == 'current':
        backup = UI.with_name('AppUITests.batch-missing')
        assert not backup.exists(); UI.rename(backup)
        try: reject(call)
        finally: backup.rename(UI)
    report['rejected'] = 6 if MODE == 'current' else 5
elif MODE == 'dependencies':
    entry.previous_directory(UI)
    for relative in ('tools/run138_editor_readiness_contract.json',
                     'Tests/ContractChecks/fixtures/project_editor_readiness.json',
                     'App/ProjectEditView.swift'):
        with change(ROOT / relative, 'same_size_mtime'): reject(call)
    file = ROOT / 'tools/run138_editor_readiness_contract.json'; read = Path.read_bytes
    def denied(path):
        if path == file: raise PermissionError('sentinel denied contract')
        return read(path)
    with patch.object(Path, 'read_bytes', denied): reject(call, 'sentinel denied contract')
    report['rejected'] = 4
elif MODE == 'during':
    cached = entry.previous_directory(UI)
    scenarios = [(ROOT / 'README.md', 'same_size_mtime', 'Current inputs changed'),
                 (ROOT / 'batch-extra-input.txt', 'add', 'Current inputs changed'),
                 (cached / 'TicketWalletFlowTests.swift', 'same_size_mtime', None),
                 (cached / 'batch-extra-input.txt', 'add', 'Historical inputs changed')]
    for path, kind, message in scenarios:
        original = history.historical_ui_source; seen = []
        with ExitStack() as changes:
            def changed(*args):
                result = original(*args)
                if not seen:
                    seen.append(True); changes.enter_context(change(path, kind))
                return result
            with patch.object(history, 'historical_ui_source', side_effect=changed): reject(call, message)
            assert seen
    report['rejected'] = len(scenarios)
elif MODE == 'alternate':
    historical = entry.previous_directory(UI)
    with patch.object(batches, 'validated_pre_run129_directory', side_effect=AssertionError('wrong batch root')):
        assert len(history.historical_ui_sources(historical)) == len(EXPECTED)
    with tempfile.TemporaryDirectory(prefix='run109-alternate-') as temporary:
        alternate = Path(temporary) / 'AppUITests'
        import shutil
        shutil.copytree(UI, alternate)
        with change(alternate / 'TicketWalletFlowTests.swift', 'same_size_mtime'), \
                patch.object(batches, 'validated_pre_run129_directory', side_effect=AssertionError('wrong batch root')):
            reject(lambda: history.historical_ui_sources(alternate), errors=(ValueError, OSError))
    report['alternate_and_historical_paths_preserved'] = True
elif MODE == 'historical_pins':
    for relative in ('tools/tests/fixtures/run109_published_sources/IntegratedNativeAcceptanceFlowTests.swift.txt',
                     'tools/tests/fixtures/pre_reviewed_features/source-index.json'):
        with change(ROOT / relative, 'same_size_mtime'): reject(call)
    report['rejected'] = 2
elif MODE == 'reader_error':
    original = history.historical_ui_source; seen = []; returned = []
    def broken(*args):
        seen.append(args)
        if len(seen) == 2: raise RuntimeError('sentinel historical reader')
        return original(*args)
    with patch.object(history, 'historical_ui_source', side_effect=broken):
        reject(lambda: returned.append(call()), 'sentinel historical reader', (RuntimeError,))
    assert len(seen) == 2 and not returned
    report['no_partial_success'] = True
else: raise AssertionError(MODE)
print(json.dumps(report))
'''


class Run109HistoricalBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from tools import run138_current_source_projection as entry
        cls.lifetime = tempfile.TemporaryDirectory(prefix='run109-batch-controls-')
        cls.addClassCleanup(cls.lifetime.cleanup)
        cls.root = Path(cls.lifetime.name) / 'source'
        shutil.copytree(ROOT, cls.root, ignore=lambda directory, names:
                        entry.ignore_context_names(ROOT, directory, names))

    def probe(self, mode):
        header = ('MODE=' + repr(mode) + '\nHELPER=' + repr(HELPER) + '\nBEFORE_SHA256=' +
                  repr(BEFORE_SHA256) + '\nBATCH_PREFIX=' + repr(BATCH_PREFIX) + '\n')
        result = subprocess.run([sys.executable, '-B', '-c', header + PROBE],
                                cwd=self.root, text=True, capture_output=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_exact_inverse_preserves_complete_original_helper(self):
        text = (ROOT / HELPER).read_text()
        self.assertEqual(text.count(BATCH_PREFIX), 1)
        old = text.replace(BATCH_PREFIX, '', 1)
        self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), BEFORE_SHA256)

    def test_all_original_output_bytes_and_fresh_admission_on_each_top_level_call(self):
        self.probe('positive')

    def test_warm_current_raw_missing_directory_membership_and_permission_fail_closed(self):
        self.probe('current')

    def test_warm_cached_raw_missing_files_membership_and_permission_fail_closed(self):
        self.probe('cached')

    def test_warm_contract_and_application_dependency_bytes_are_reauthenticated(self):
        self.probe('dependencies')

    def test_mid_scan_same_mtime_bytes_and_membership_changes_fail_before_return(self):
        self.probe('during')

    def test_alternate_and_historical_directories_never_borrow_current_batch_inputs(self):
        self.probe('alternate')

    def test_original_historical_source_and_index_pins_remain_required(self):
        self.probe('historical_pins')

    def test_historical_reader_failure_never_returns_partial_success(self):
        self.probe('reader_error')


if __name__ == '__main__':
    unittest.main()

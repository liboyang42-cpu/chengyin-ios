#!/usr/bin/env python3
"""Bounded export; an incomplete bundle never becomes a successful test receipt."""
import argparse
import json
import pathlib
import subprocess
import os
import signal


def export(root):
    root = pathlib.Path(root)
    output = root / 'questify-ui-attachments'
    evidence = root / 'questify-ui-evidence'
    if output.is_symlink() or evidence.is_symlink():
        raise ValueError('Refusing symlink artifact directory')
    status_path = evidence / 'export-status.json'
    if status_path.is_symlink():
        raise ValueError('Refusing symlink artifact status file')
    output.mkdir(exist_ok=True)
    evidence.mkdir(exist_ok=True)
    bundle = root / 'questify-ui-results.xcresult'
    status = {'version': 1, 'diagnostic_only': True, 'test_success_claimed': False,
              'bundle_finalized': (bundle / 'Info.plist').is_file(),
              'export': 'not-finalized', 'screenshot_fallback': 'omitted-not-failure-state',
              'termination_confirmed': None, 'retained_files': 0, 'retained_bytes': 0}
    # No simulator screenshot fallback: it depicts a later screen, and run96's
    # fallback stalled waiting for surfaces after XCTest interrupted the runner.
    if status['bundle_finalized']:
        try:
            process = subprocess.Popen(['xcrun', 'xcresulttool', 'export', 'attachments',
                                        '--path', str(bundle), '--output-path', str(output)],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
            try:
                code = process.wait(timeout=35)
                status['export'] = 'exported' if code == 0 else 'failed'
            except subprocess.TimeoutExpired:
                status['export'] = 'timeout'
                # Signal the whole isolated export group, including xcrun children.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                    status['termination_confirmed'] = True
                except subprocess.TimeoutExpired:
                    status['termination_confirmed'] = False
        except OSError:
            status['export'] = 'unavailable'
    # Keep existing synthetic fixture images, bounded to 24 MiB / 128 files.
    # Arbitrary xcresult text/manifest metadata is not part of this small packet.
    for path in sorted(output.rglob('*')):
        if path.is_symlink():
            path.unlink()
        elif path.is_file():
            size = path.stat().st_size
            if (path.suffix.lower() not in {'.png', '.jpg'} or status['retained_files'] >= 128 or
                    status['retained_bytes'] + size > 24 * 1024 * 1024):
                path.unlink()
            else:
                status['retained_files'] += 1
                status['retained_bytes'] += size
    status_path.write_text(json.dumps(status, sort_keys=True) + '\n')
    return status

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner-temp', type=pathlib.Path, required=True)
    export(parser.parse_args().runner_temp)

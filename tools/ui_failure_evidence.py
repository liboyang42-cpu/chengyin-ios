"""Persist only a closed-schema synthetic AX projection, independently of xcresult."""
import json
import os
import pathlib
import sys
import threading

PREFIX = b'QUESTIFY_UI_EVIDENCE_V1 '
TYPES = {'StaticText', 'Button', 'Other', 'NavigationBar', 'ScrollView', 'Table', 'Cell'}
STRINGS = {'Order number, OFFLINE-WAITLIST-9417', '订单号, OFFLINE-WAITLIST-9417',
           'Order number', '订单号', 'OFFLINE-WAITLIST-9417',
           'registration.waitlist.order.close', 'profile.order.detail.retry',
           'registration.waitlist.openOrder'}

def validate(raw):
    if len(raw) > 32768:
        return None
    try:
        data = json.loads(raw)
        if (set(data) != {'version', 'fixture', 'rows', 'sourceTruncated'} or
                type(data['version']) is not int or data['version'] != 1 or
                data['fixture'] != 'registration-waitlist' or
                type(data['sourceTruncated']) is not bool or
                not isinstance(data['rows'], list) or len(data['rows']) > 128):
            return None
        for row in data['rows']:
            if (set(row) != {'type', 'knownStrings'} or row['type'] not in TYPES or
                    not isinstance(row['knownStrings'], list) or len(row['knownStrings']) > len(STRINGS) or
                    any(type(value) is not str or value not in STRINGS for value in row['knownStrings'])):
                return None
        return data
    except (ValueError, TypeError, KeyError, RecursionError):
        return None

class EvidenceStream:
    def __init__(self, directory):
        self.directory = pathlib.Path(directory)
        if self.directory.is_symlink():
            raise ValueError("Evidence directory must not be a symlink")
        self.directory.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()
        self.records = []
        self.code = None
        self.persistence_failed = False
        self.write()

    def write(self):
        try:
            self._write()
        except OSError:
            # Evidence storage cannot stop stdout draining or alter test results.
            self.persistence_failed = True
            print('UI evidence persistence unavailable; test execution remains authoritative', file=sys.stderr)

    def _write(self):
        data = {'version': 1, 'diagnostic_only': True, 'exit_code': self.code,
                'complete': False, 'persistence_failed': self.persistence_failed, 'record_limit': 8, 'records': self.records}
        target = self.directory / 'failure-ax.json'
        temporary = target.with_suffix('.tmp')
        if self.directory.is_symlink() or temporary.is_symlink() or target.is_symlink():
            raise OSError('Unsafe evidence path')
        with temporary.open('w') as output:
            json.dump(data, output, ensure_ascii=True)
            output.flush()
            os.fsync(output.fileno())
        temporary.replace(target)

    def accept(self, line):
        # A single dedicated marker line, never a search through arbitrary output.
        if not line.startswith(PREFIX):
            return
        data = validate(line[len(PREFIX):])
        if data is not None:
            with self.lock:
                if len(self.records) < 8:
                    self.records.append(data)
                    self.write()

    def start(self, pipe):
        def pump():
            fragmented = False
            while True:
                line = pipe.readline(65536)
                if not line:
                    break
                # Preserve existing job log output, but never copy it to the artifact.
                sys.stdout.buffer.write(line)
                sys.stdout.buffer.flush()
                if not fragmented and line.endswith(b'\n'):
                    self.accept(line)
                fragmented = not line.endswith(b'\n')
        self.thread = threading.Thread(target=pump, daemon=True)
        self.thread.start()

    def finish(self, code):
        self.thread.join(timeout=1)
        with self.lock:
            self.code = code
            self.write()

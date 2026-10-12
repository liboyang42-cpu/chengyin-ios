"""Bounded pure compression reuse; source/admission checks remain with callers.

Entries retain only an immutable compressed/base85 pair created from the same
input. Every hit checks the encoded integrity and compares a bounded decoding
of compressed bytes to the supplied actual bytes. No decoded source is retained.
"""
import base64
from collections import OrderedDict
from dataclasses import dataclass
import hashlib
from threading import RLock
import zlib

MAX_ENTRIES = 8
MAX_RETAINED_BYTES = 6 * 1024 * 1024
_PAYLOAD_DIGEST = hashlib.sha256


@dataclass(frozen=True, init=False, slots=True)
class _Encoding:
    compressed: bytes
    encoded: bytes
    encoded_digest: bytes
    weight: int

    def __init__(self, raw):
        if type(raw) is not bytes:
            raise TypeError('Frozen source input must be immutable bytes')
        compressed = zlib.compress(raw, 9)
        encoded = base64.b85encode(compressed)
        object.__setattr__(self, 'compressed', compressed)
        object.__setattr__(self, 'encoded', encoded)
        object.__setattr__(self, 'encoded_digest', _PAYLOAD_DIGEST(encoded).digest())
        # Include the key digest, integer length and encoded integrity digest.
        object.__setattr__(self, 'weight', len(compressed) + len(encoded) + 32 + 8 + 32)

    def matches(self, raw):
        try:
            if (type(self.compressed) is not bytes or type(self.encoded) is not bytes
                    or type(self.encoded_digest) is not bytes or len(self.encoded_digest) != 32
                    or type(self.weight) is not int
                    or self.weight != len(self.compressed) + len(self.encoded) + 72
                    or _PAYLOAD_DIGEST(self.encoded).digest() != self.encoded_digest):
                return False
            stream = zlib.decompressobj()
            restored = stream.decompress(self.compressed, len(raw) + 1)
            return (stream.eof and not stream.unused_data and not stream.unconsumed_tail
                    and restored == raw)
        except (AttributeError, ValueError, zlib.error):
            return False


class LargeEncodingCache:
    def __init__(self):
        self._entries = OrderedDict()
        self._retained = 0
        self._lock = RLock()

    def info(self):
        with self._lock:
            return {'entries': len(self._entries), 'retained_bytes': self._retained}

    def clear(self):
        with self._lock:
            self._entries.clear()
            self._retained = 0

    def encode(self, raw):
        if type(raw) is not bytes:
            raise TypeError('Frozen source input must be immutable bytes')
        key = (len(raw), hashlib.sha256(raw).digest())
        with self._lock:
            existing = self._entries.get(key)
        if type(existing) is _Encoding and existing.matches(raw):
            with self._lock:
                if self._entries.get(key) is existing:
                    self._entries.move_to_end(key)
            return existing.encoded
        entry = _Encoding(raw)
        with self._lock:
            old = self._entries.pop(key, None)
            if old is not None:
                # Unexpected/modified entries never supply output or accounting.
                self._entries.clear()
                self._retained = 0
            if entry.weight <= MAX_RETAINED_BYTES:
                while self._entries and (len(self._entries) >= MAX_ENTRIES
                        or self._retained + entry.weight > MAX_RETAINED_BYTES):
                    _, evicted = self._entries.popitem(last=False)
                    self._retained -= evicted.weight
                self._entries[key] = entry
                self._retained += entry.weight
        return entry.encoded


_CACHE = LargeEncodingCache()


def encode_large_source(raw):
    return _CACHE.encode(raw)

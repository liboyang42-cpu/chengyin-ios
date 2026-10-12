"""Exact pure codec results and bounded reuse; no source-admission caching."""
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
from pathlib import Path
import tempfile
import os
import unittest
from unittest.mock import patch
import zlib
from tools import history_large_codec as codec


class LargeHistoryCodecTests(unittest.TestCase):
    def setUp(self):
        self.cache = codec.LargeEncodingCache()

    def test_large_and_small_results_equal_original_algorithm(self):
        for raw in [b'', bytes(range(256)), '中文汉语'.encode() * 200000,
                    hashlib.shake_256(b'entropy').digest(1024 * 1024 + 1)]:
            expected = base64.b85encode(zlib.compress(raw, 9))
            self.assertEqual(self.cache.encode(raw), expected)
            self.assertEqual(self.cache.encode(raw), expected)

    def test_hit_rechecks_decoded_actual_input_without_recompressing(self):
        raw = b'actual immutable source' * 60000
        expected = self.cache.encode(raw)
        with patch.object(codec.zlib, 'compress', side_effect=AssertionError('Unexpected re-compression')):
            self.assertEqual(self.cache.encode(raw), expected)
        with patch.object(codec._Encoding, 'matches', return_value=False), patch.object(codec.zlib, 'compress', wraps=zlib.compress) as compress:
            self.assertEqual(self.cache.encode(raw), expected)
            self.assertEqual(compress.call_count, 1)

    def test_only_exact_immutable_bytes_are_accepted_cold_and_warm(self):
        class BytesSubclass(bytes):
            pass
        self.cache.encode(b'x')
        for value in [bytearray(b'x'), memoryview(b'x'), BytesSubclass(b'x'), 'x', {}, None]:
            before = self.cache.info()
            with self.assertRaises(TypeError): self.cache.encode(value)
            self.assertEqual(self.cache.info(), before)

    def test_actual_same_size_mtime_replacement_and_missing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source'; path.write_bytes(b'a' * 1200000)
            stat = path.stat(); before = self.cache.encode(path.read_bytes())
            path.write_bytes(b'b' * 1200000); os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            after = self.cache.encode(path.read_bytes())
            self.assertNotEqual(before, after)
            self.assertEqual(zlib.decompress(base64.b85decode(after)), path.read_bytes())
            path.unlink()
            with self.assertRaises(FileNotFoundError): self.cache.encode(path.read_bytes())

    def test_digest_collision_cannot_substitute_different_input(self):
        class Collision:
            def digest(self): return b'x' * 32
        with patch.object(codec.hashlib, 'sha256', return_value=Collision()):
            first = self.cache.encode(b'a' * 1200000)
            second = self.cache.encode(b'b' * 1200000)
            self.assertNotEqual(first, second)
            self.assertEqual(zlib.decompress(base64.b85decode(second)), b'b' * 1200000)

    def matches_compressed(self, compressed, raw):
        entry = codec._Encoding(raw)
        object.__setattr__(entry, 'compressed', compressed)
        object.__setattr__(entry, 'weight', len(compressed) + len(entry.encoded) + 72)
        return entry.matches(raw)

    def test_entry_is_immutable_and_polluted_base85_cannot_be_returned(self):
        raw = b'canonical source' * 100000
        expected = self.cache.encode(raw)
        key = next(iter(self.cache._entries)); entry = self.cache._entries[key]
        with self.assertRaises(AttributeError): entry.encoded = b'wrong'
        # Deliberately bypass frozen storage to exercise the integrity rejection.
        object.__setattr__(entry, 'encoded', b'x' * len(entry.encoded))
        self.assertEqual(self.cache.encode(raw), expected)
        self.assertEqual(self.cache.info()['retained_bytes'], self.cache._entries[key].weight)
        self.cache._entries[key] = (zlib.compress(raw), b'wrong output')
        self.assertEqual(self.cache.encode(raw), expected)
        self.assertIs(type(self.cache._entries[key]), codec._Encoding)

    def test_invalid_trailing_stream_and_oversized_expansion_rejected(self):
        raw = b'x' * 1200000
        encoded = self.cache.encode(raw)
        for compressed in [b'bad', zlib.compress(raw) + b'trailing', zlib.compress(raw) + zlib.compress(raw), zlib.compress(raw * 2)]:
            self.assertFalse(self.matches_compressed(compressed, raw))
        self.assertFalse(self.matches_compressed(base64.b85decode(encoded)[:-3], raw))
        self.assertFalse(self.matches_compressed(b' ', raw))

    def test_lru_and_weight_bound_never_retain_decoded_inputs(self):
        for index in range(codec.MAX_ENTRIES * 3):
            self.cache.encode(bytes([index]) * 1200000)
        self.assertEqual(self.cache.info()['entries'], codec.MAX_ENTRIES)
        self.assertLessEqual(self.cache.info()['retained_bytes'], codec.MAX_RETAINED_BYTES)
        for key, value in self.cache._entries.items():
            self.assertEqual(len(key[1]), 32)
            self.assertEqual(key[0], 1200000)
            self.assertIs(type(value), codec._Encoding)
            self.assertTrue(all(type(item) is bytes for item in (value.compressed, value.encoded)))
            self.assertLess(len(value.compressed) + len(value.encoded), 1200000)
            self.assertEqual(base64.b85encode(value.compressed), value.encoded)
        self.assertEqual(self.cache.info()['retained_bytes'], sum(value.weight for value in self.cache._entries.values()))

    def test_large_incompressible_output_bypasses_retention(self):
        raw = hashlib.shake_256(b'oversized codec entry').digest(codec.MAX_RETAINED_BYTES)
        expected = base64.b85encode(zlib.compress(raw, 9))
        self.assertGreater(len(expected), codec.MAX_RETAINED_BYTES)
        self.assertEqual(self.cache.encode(raw), expected)
        self.assertEqual(self.cache.info(), {'entries': 0, 'retained_bytes': 0})

    def test_combined_legacy_and_large_payload_budget_stays_below_40mib(self):
        n = 1024 * 1024
        compress_bound = n + (n >> 12) + (n >> 14) + (n >> 25) + 13
        encode_bound = 8 * (n + ((compress_bound + 3) // 4) * 5)
        decode_bound = 8 * (n + ((n + 4) // 5) * 4)
        self.assertLessEqual(encode_bound + decode_bound + codec.MAX_RETAINED_BYTES, 40 * 1024 * 1024)

    def test_concurrent_equal_and_distinct_inputs_remain_exact_and_bounded(self):
        inputs = [str(index % 5).encode() * 1100000 for index in range(25)]
        with ThreadPoolExecutor(max_workers=8) as workers:
            results = list(workers.map(self.cache.encode, inputs))
        for raw, encoded in zip(inputs, results):
            self.assertEqual(encoded, base64.b85encode(zlib.compress(raw, 9)))
        self.assertLessEqual(self.cache.info()['entries'], codec.MAX_ENTRIES)
        self.assertLessEqual(self.cache.info()['retained_bytes'], codec.MAX_RETAINED_BYTES)
        self.cache.clear(); self.assertEqual(self.cache.info(), {'entries': 0, 'retained_bytes': 0})

    def test_actual_current_large_registration_source_matches_uncached_bytes(self):
        source = Path(__file__).resolve().parents[2] / 'Tests/ContractChecks/test_category_roam_registration.py'
        raw = source.read_bytes(); self.assertGreater(len(raw), 1024 * 1024)
        expected = base64.b85encode(zlib.compress(raw, 9))
        self.assertEqual(codec.encode_large_source(raw), expected)
        self.assertEqual(codec.encode_large_source(raw), expected)

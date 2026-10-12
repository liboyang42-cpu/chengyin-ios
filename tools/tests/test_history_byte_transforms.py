"""Pure-transform controls; filesystem admission remains with each caller."""
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
import zlib

from Tests.ContractChecks import test_category_roam_registration as transforms


class HistoryByteTransformTests(unittest.TestCase):
    def setUp(self):
        transforms._encoded_bytes.cache_clear()
        transforms._compressed_bytes.cache_clear()

    def test_encodings_are_byte_identical_to_original_operations(self):
        root = Path(__file__).resolve().parents[2]
        samples = (b'', bytes(range(256)), '原始字节\n'.encode(),
                   (root / 'Tests/ContractChecks/test_category_roam_registration.py').read_bytes())
        for raw in samples:
            expected = base64.b85encode(zlib.compress(raw, 9))
            self.assertEqual(transforms.encode_frozen_source(raw), expected)
            self.assertEqual(transforms.decode_frozen_source(expected), raw)
            self.assertEqual(transforms.encode_frozen_source(raw), expected)
            self.assertEqual(transforms.decode_frozen_source(expected), raw)
        encoded_hits = sum(len(raw) <= transforms.MAX_INPUT_BYTES for raw in samples)
        decoded_hits = sum(len(base64.b85encode(zlib.compress(raw, 9))) <= transforms.MAX_INPUT_BYTES
                           for raw in samples)
        self.assertEqual(transforms._encoded_bytes.cache_info().hits, encoded_hits)
        self.assertEqual(transforms._compressed_bytes.cache_info().hits, decoded_hits)

    def test_only_immutable_byte_inputs_and_outputs_are_accepted(self):
        for value in (bytearray(b'input'), memoryview(b'input'), 'input', {}):
            for function in (transforms.encode_frozen_source, transforms.decode_frozen_source):
                with self.assertRaises(TypeError):
                    function(value)
        encoded = transforms.encode_frozen_source(b'input')
        self.assertIs(type(encoded), bytes)
        self.assertIs(type(transforms.decode_frozen_source(encoded)), bytes)

    def test_replacement_with_same_size_and_mtime_uses_new_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source'
            path.write_bytes(b'original input')
            metadata = path.stat()
            old = transforms.encode_frozen_source(path.read_bytes())
            path.write_bytes(b'modified input')
            os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            self.assertEqual(path.stat().st_size, metadata.st_size)
            self.assertEqual(path.stat().st_mtime_ns, metadata.st_mtime_ns)
            changed = transforms.encode_frozen_source(path.read_bytes())
            self.assertNotEqual(changed, old)
            self.assertEqual(transforms.decode_frozen_source(changed), b'modified input')
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                transforms.encode_frozen_source(path.read_bytes())

    def test_lru_entry_count_and_per_input_limit_are_bounded(self):
        for index in range(transforms.MAX_ENTRIES * 3):
            raw = str(index).encode()
            encoded = transforms.encode_frozen_source(raw)
            self.assertEqual(transforms.decode_frozen_source(encoded), raw)
        for cache in (transforms._encoded_bytes, transforms._compressed_bytes):
            self.assertEqual(cache.cache_info().maxsize, transforms.MAX_ENTRIES)
            self.assertEqual(cache.cache_info().currsize, transforms.MAX_ENTRIES)
        encode_before = transforms._encoded_bytes.cache_info()
        large = b'x' * (transforms.MAX_INPUT_BYTES + 1)
        encoded = transforms.encode_frozen_source(large)
        self.assertEqual(encoded, base64.b85encode(zlib.compress(large, 9)))
        self.assertEqual(transforms._encoded_bytes.cache_info(), encode_before)
        # A high-entropy payload makes the encoded input exceed the decode cap.
        random = hashlib.shake_256(b'bounded decoder test').digest(transforms.MAX_INPUT_BYTES)
        large_encoded = base64.b85encode(zlib.compress(random, 9))
        self.assertGreater(len(large_encoded), transforms.MAX_INPUT_BYTES)
        decode_before = transforms._compressed_bytes.cache_info()
        self.assertEqual(transforms.decode_frozen_source(large_encoded), random)
        self.assertEqual(transforms._compressed_bytes.cache_info(), decode_before)

    def test_private_cache_entrypoints_also_reject_oversized_or_nonbyte_keys(self):
        large = b'x' * (transforms.MAX_INPUT_BYTES + 1)
        for cache in (transforms._encoded_bytes, transforms._compressed_bytes):
            before = cache.cache_info().currsize
            for value in (large, 'text'):
                with self.assertRaises(ValueError):
                    cache(value)
            self.assertEqual(cache.cache_info().currsize, before)

    def test_private_cache_typed_keys_reject_subclass_and_readonly_views_cold_or_warm(self):
        class ByteSubclass(bytes):
            pass
        raw = b'typed immutable input'
        encoded = base64.b85encode(zlib.compress(raw, 9))
        for cache, value in ((transforms._encoded_bytes, raw), (transforms._compressed_bytes, encoded)):
            for warm in (False, True):
                cache.cache_clear()
                if warm:
                    cache(value)
                before = cache.cache_info()
                for changed in (ByteSubclass(value), memoryview(value)):
                    self.assertEqual(changed, value)
                    with self.subTest(cache=cache.__name__, warm=warm, kind=type(changed).__name__):
                        with self.assertRaises(ValueError):
                            cache(changed)
                self.assertEqual(cache.cache_info().hits, before.hits)
                self.assertEqual(cache.cache_info().currsize, before.currsize)
                for public in (transforms.encode_frozen_source, transforms.decode_frozen_source):
                    for changed in (ByteSubclass(value), memoryview(value)):
                        with self.assertRaises(TypeError):
                            public(changed)

    def test_large_expansion_is_never_stored_as_a_decoded_source(self):
        raw = b'zero' * transforms.MAX_INPUT_BYTES
        encoded = base64.b85encode(zlib.compress(raw, 9))
        self.assertLess(len(encoded), transforms.MAX_INPUT_BYTES)
        self.assertEqual(transforms.decode_frozen_source(encoded), raw)
        cached_compressed = transforms._compressed_bytes(encoded)
        self.assertEqual(cached_compressed, base64.b85decode(encoded))
        self.assertLess(len(cached_compressed), len(encoded))
        self.assertEqual(transforms._encoded_bytes.cache_info().currsize, 0)

    def test_mutated_or_invalid_encoded_bytes_do_not_reuse_healthy_entry(self):
        encoded = transforms.encode_frozen_source(b'healthy source')
        self.assertEqual(transforms.decode_frozen_source(encoded), b'healthy source')
        for changed in (b' ' + encoded[1:], encoded[:-5], b''):
            with self.assertRaises((ValueError, zlib.error)):
                transforms.decode_frozen_source(changed)
        self.assertEqual(transforms.decode_frozen_source(encoded), b'healthy source')

    def test_threads_reuse_only_equal_immutable_payloads(self):
        inputs = [str(index % 5).encode() * 1000 for index in range(80)]
        def round_trip(raw):
            encoded = transforms.encode_frozen_source(raw)
            self.assertEqual(encoded, base64.b85encode(zlib.compress(raw, 9)))
            return transforms.decode_frozen_source(encoded)
        with ThreadPoolExecutor(max_workers=8) as workers:
            self.assertEqual(list(workers.map(round_trip, inputs)), inputs)
        self.assertGreater(transforms._encoded_bytes.cache_info().hits, 0)
        self.assertGreater(transforms._compressed_bytes.cache_info().hits, 0)
        self.assertLessEqual(transforms._encoded_bytes.cache_info().currsize, transforms.MAX_ENTRIES)
        self.assertLessEqual(transforms._compressed_bytes.cache_info().currsize, transforms.MAX_ENTRIES)


class Native54ByteTransformClosureTests(unittest.TestCase):
    def test_five_complete_current_sources_restore_exact_published_native54_bytes(self):
        self.assertEqual(transforms.BYTE_CACHE_BASE_COMMIT, '54f708eb260ad20cdf0fb6355cc4eaedb967019a')
        self.assertEqual(set(transforms.BYTE_CACHE_PRE_SHA256), {
            transforms.SELF_PATH, transforms.CATEGORY_GATE, transforms.PROFILE_PATH,
            transforms.RUNNER_PATH, transforms.CONTRACT_PATH})
        for name, expected in transforms.BYTE_CACHE_PRE_SHA256.items():
            raw = (transforms.ROOT / name).read_bytes()
            with self.subTest(path=name):
                old = transforms.byte_cache_predecessor_source(name, raw)
                self.assertEqual(hashlib.sha256(old).hexdigest(), expected)
                self.assertEqual((transforms.ROOT / name).read_bytes(), raw)

    def test_original_functions_tests_and_read_operations_are_preserved(self):
        import ast
        raw = (transforms.ROOT / transforms.SELF_PATH).read_bytes()
        old = ast.parse(transforms._byte_cache_category_preimage(raw))
        new = ast.parse(raw)
        functions = lambda tree: [node for node in ast.walk(tree)
                                  if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
        old_functions, new_functions = functions(old), functions(new)
        current = {(node.name, node.lineno): node for node in new_functions}
        for original in old_functions:
            matches = [node for node in new_functions if node.name == original.name]
            self.assertTrue(any(ast.dump(node.args) == ast.dump(original.args) for node in matches), original.name)
            if original.name.startswith('test_'):
                self.assertTrue(any(ast.dump(node) == ast.dump(original) for node in matches), original.name)
        reads = lambda tree: sum(isinstance(node, ast.Attribute) and node.attr == 'read_bytes'
                                 for node in ast.walk(tree))
        for name in ('_decoded_external_template', 'native_predecessor_source',
                     'description_predecessor_source', 'actor_predecessor_source', 'album_predecessor_source'):
            original = next(node for node in old.body if isinstance(node, ast.FunctionDef) and node.name == name)
            changed = next(node for node in new.body if isinstance(node, ast.FunctionDef) and node.name == name)
            self.assertEqual(reads(original), reads(changed), name)
            require_messages = lambda node: [ast.dump(item.args[-1]) for item in ast.walk(node)
                 if isinstance(item, ast.Call) and isinstance(item.func, ast.Name) and item.func.id == 'require']
            self.assertEqual(require_messages(original), require_messages(changed), name)

    def test_damaged_inverse_constants_are_rechecked_after_transform_cache_warmup(self):
        from unittest.mock import patch
        raw = (transforms.ROOT / transforms.SELF_PATH).read_bytes()
        transforms._decoded_external_template((transforms.ROOT / transforms.CATEGORY_GATE).read_bytes())
        expected = transforms._byte_cache_category_preimage(raw)
        before, after = transforms.BYTE_CACHE_SOURCE_HUNKS[0]
        damaged = ((before + '\n', after),) + transforms.BYTE_CACHE_SOURCE_HUNKS[1:]
        with patch.object(transforms, 'BYTE_CACHE_SOURCE_HUNKS', damaged):
            with self.assertRaises(AssertionError):
                transforms._byte_cache_category_preimage(raw)
        self.assertEqual(transforms._byte_cache_category_preimage(raw), expected)

    def test_warm_cache_rechecks_same_size_mtime_and_missing_current_boundary_files(self):
        current = (transforms.ROOT / transforms.CONTRACT_PATH).read_bytes()
        transforms.checked_current(current, transforms.ROOT)
        for name in transforms.BYTE_CACHE_PRE_SHA256:
            path = transforms.ROOT / name
            raw, metadata = path.read_bytes(), path.stat()
            try:
                path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
                os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                self.assertEqual(path.stat().st_size, metadata.st_size)
                self.assertEqual(path.stat().st_mtime_ns, metadata.st_mtime_ns)
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    transforms.checked_current(current, transforms.ROOT)
            finally:
                path.write_bytes(raw)
                os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            backup = path.with_name(path.name + '.byte-transform-missing-control')
            self.assertFalse(backup.exists())
            path.rename(backup)
            try:
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    transforms.checked_current(current, transforms.ROOT)
            finally:
                backup.rename(path)
        transforms.checked_current(current, transforms.ROOT)

    def test_threaded_entry_rechecks_current_raw_after_cache_warmup(self):
        current = (transforms.ROOT / transforms.CONTRACT_PATH).read_bytes()
        path = transforms.ROOT / transforms.CATEGORY_GATE
        raw, metadata = path.read_bytes(), path.stat()
        with ThreadPoolExecutor(max_workers=1) as worker:
            worker.submit(transforms.checked_current, current, transforms.ROOT).result()
            try:
                path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
                os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    worker.submit(transforms.checked_current, current, transforms.ROOT).result()
            finally:
                path.write_bytes(raw)
                os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            worker.submit(transforms.checked_current, current, transforms.ROOT).result()



if __name__ == '__main__':
    unittest.main()

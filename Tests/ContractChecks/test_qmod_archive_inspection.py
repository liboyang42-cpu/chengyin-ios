"""Fixture and source guards for the local qmod archive inspection.

These checks do not compile Swift or run XCTest. They prove the committed
fixtures carry the hostile cases and that the new sources stay local:
no upload, no package execution, no H5 acceptance, and no business-rule claim.
"""
import hashlib
import io
import json
import stat
import struct
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Tests" / "Resources" / "QmodArchiveInspection"
CORE = ROOT / "Core" / "QmodArchiveInspection.swift"
APP = ROOT / "App" / "QmodAuthorImportView.swift"
CONTRACT = ROOT / "Core" / "QmodManifestContract.swift"
WHEN = (2026, 10, 21, 0, 0, 0)


def sha256(payload):
    return hashlib.sha256(payload).hexdigest()


def manifest_bytes(files, kind="questify.mod", bad_hash_for=None):
    listed = []
    for path, payload in files:
        digest = "ab" * 32 if path == bad_hash_for else sha256(payload)
        listed.append({"path": path, "sha256": digest, "bytes": len(payload)})
    body = {
        "formatVersion": "1.0",
        "kind": kind,
        "packageId": "bookshop.mystery",
        "packageVersion": "1.2.0",
        "entrypoint": "content.json",
        "locales": ["zh-Hans", "en"],
        "runtime": {"minHostVersion": "1.0.0", "capabilities": ["choice"]},
        "files": listed,
        "rightsDeclaration": {"declared": True},
        "monetizationDeclaration": "NONE",
    }
    return json.dumps(body, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def base_files(content=b'{"nodes":[]}', cover=b"webp-bytes"):
    return [
        ("content.json", content),
        ("zh-Hans.json", '{"title":"local"}'.encode()),
        ("en.json", b'{"title":"local"}'),
        ("assets/cover.webp", cover),
    ]


def build_zip(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, payload, method, attr in entries:
            info = zipfile.ZipInfo(name, date_time=WHEN)
            info.compress_type = method
            if attr is not None:
                info.create_system = 3
                info.external_attr = attr
            archive.writestr(info, payload)
    return buffer.getvalue()


def regular(name, payload, method=zipfile.ZIP_STORED):
    return (name, payload, method, (stat.S_IFREG | 0o644) << 16)


def package(files, kind="questify.mod", method=zipfile.ZIP_STORED, extra=(), bad_hash_for=None):
    manifest = manifest_bytes(files, kind=kind, bad_hash_for=bad_hash_for)
    entries = [regular("manifest.json", manifest, method)]
    entries.extend(regular(path, payload, method) for path, payload in files)
    entries.extend(extra)
    return build_zip(entries)


def set_encryption_flag(blob, name):
    data = bytearray(blob)
    name_b = name.encode("utf-8")
    start = 0
    while True:
        sig = data.find(b"PK\x03\x04", start)
        if sig < 0:
            break
        name_len = struct.unpack_from("<H", data, sig + 26)[0]
        if bytes(data[sig + 30:sig + 30 + name_len]) == name_b:
            flags = struct.unpack_from("<H", data, sig + 6)[0] | 1
            struct.pack_into("<H", data, sig + 6, flags)
        start = sig + 4
    start = 0
    while True:
        sig = data.find(b"PK\x01\x02", start)
        if sig < 0:
            break
        name_len = struct.unpack_from("<H", data, sig + 28)[0]
        if bytes(data[sig + 46:sig + 46 + name_len]) == name_b:
            flags = struct.unpack_from("<H", data, sig + 8)[0] | 1
            struct.pack_into("<H", data, sig + 8, flags)
        start = sig + 4
    return bytes(data)


def corrupt_crc(blob, name):
    wrong = 0x01020304
    data = bytearray(blob)
    name_b = name.encode("utf-8")
    for signature, name_at, crc_at, name_len_at in (
        (b"PK\x03\x04", 30, 14, 26),
        (b"PK\x01\x02", 46, 16, 28),
    ):
        start = 0
        while True:
            sig = data.find(signature, start)
            if sig < 0:
                break
            name_len = struct.unpack_from("<H", data, sig + name_len_at)[0]
            if bytes(data[sig + name_at:sig + name_at + name_len]) == name_b:
                struct.pack_into("<I", data, sig + crc_at, wrong)
            start = sig + 4
    return bytes(data)


def write_fixtures(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    files = base_files()
    (directory / "ok-stored.zip").write_bytes(package(files))
    (directory / "ok-deflate.zip").write_bytes(package(files, method=zipfile.ZIP_DEFLATED))
    hostile = [
        regular("../evil.json", b"x"),
        regular("/abs.json", b"x"),
        regular("a\\b.json", b"x"),
        regular("foo/../../x.json", b"x"),
    ]
    (directory / "traversal.zip").write_bytes(package(files, extra=hostile))
    (directory / "duplicate.zip").write_bytes(package(files, extra=[regular("Content.json", b"other")]))
    pad = b"\0" * 200_000
    ratio_files = files + [("assets/pad.bin", pad)]
    manifest = manifest_bytes(ratio_files)
    entries = [regular("manifest.json", manifest)]
    entries.extend(regular(path, payload) for path, payload in files)
    entries.append(regular("assets/pad.bin", pad, zipfile.ZIP_DEFLATED))
    (directory / "ratio.zip").write_bytes(build_zip(entries))
    link = ("assets/alias.json", b"content.json", zipfile.ZIP_STORED, (stat.S_IFLNK | 0o777) << 16)
    (directory / "symlink.zip").write_bytes(package(files, extra=[link]))
    (directory / "corrupt-crc.zip").write_bytes(corrupt_crc(package(files), "content.json"))
    stored = package(files)
    (directory / "truncated.zip").write_bytes(stored[:-40])
    (directory / "hash-mismatch.zip").write_bytes(package(files, bad_hash_for="content.json"))
    (directory / "h5.zip").write_bytes(package(files, kind="questify.h5"))
    (directory / "script.zip").write_bytes(package(files, extra=[regular("run.js", b"console.log(1)\n")]))
    (directory / "encrypted.zip").write_bytes(set_encryption_flag(package(files, extra=[regular("assets/secret.bin", b"secret")]), "assets/secret.bin"))
    swap_a = [("content.json", b'{"id":"a"}'), ("zh-Hans.json", b'{"title":"a"}'), ("en.json", b'{"title":"a"}'), ("assets/only-a.webp", b"a")]
    swap_b = [("content.json", b'{"id":"b"}'), ("zh-Hans.json", b'{"title":"b"}'), ("en.json", b'{"title":"b"}'), ("assets/only-b.webp", b"b")]
    (directory / "swap-a.zip").write_bytes(package(swap_a))
    (directory / "swap-b.zip").write_bytes(package(swap_b))


def names(blob):
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        return archive.namelist()


class QmodArchiveInspectionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = CORE.read_text(encoding="utf-8")
        cls.app = APP.read_text(encoding="utf-8")
        cls.contract = CONTRACT.read_text(encoding="utf-8")

    def test_sources_stay_local_and_reuse_the_manifest_contract(self):
        for label, text in (("core", self.core), ("app", self.app)):
            for forbidden in ("URLSession", "URLRequest", "WKWebView", "JSContext", "Process(", "dlopen", "http://", "https://", "api/", "AppSession", "MineView", "AccountView"):
                self.assertNotIn(forbidden, text, f"{label} {forbidden}")
        self.assertIn("case notAttempted", self.core)
        self.assertIn("limitsAreBusinessRules = false", self.core)
        self.assertIn("acceptedH5 = false", self.core)
        self.assertIn("uploaded = false", self.core)
        self.assertIn("executedPackageCode = false", self.core)
        self.assertIn("0o120000", self.core)
        self.assertIn("isTraversal", self.core)
        self.assertLess(self.core.index("abnormalCompression"), self.core.index("QmodRawDeflate.inflate"))
        self.assertIn('if kind == "questify.h5" { throw QmodManifestIssue.h5DesignOnly }', self.contract)
        self.assertIn("isProposal: true", self.contract)
        self.assertIn("QmodManifest(data:", self.core)
        self.assertIn("fileImporter", self.app)
        self.assertIn("fixedServerDenialText", self.app)
        self.assertIn("不是正式业务规则", self.app)
        self.assertNotIn("UploadModDraft(", self.core + self.app)
        self.assertNotIn("ValidateModPackage(", self.core + self.app)

    def test_fixtures_encode_the_acceptance_cases(self):
        self.assertTrue(FIXTURES.is_dir(), FIXTURES)
        ok = zipfile.ZipFile(FIXTURES / "ok-stored.zip")
        self.assertEqual(ok.testzip(), None)
        manifest = json.loads(ok.read("manifest.json"))
        self.assertEqual(manifest["kind"], "questify.mod")
        self.assertTrue(manifest["rightsDeclaration"]["declared"] is True)
        for item in manifest["files"]:
            payload = ok.read(item["path"])
            self.assertEqual(hashlib.sha256(payload).hexdigest(), item["sha256"])
            self.assertEqual(len(payload), item["bytes"])
            info = ok.getinfo(item["path"])
            self.assertLessEqual(info.file_size, max(info.compress_size, 1) * 100)
            self.assertNotEqual((info.external_attr >> 16) & 0o170000, 0o120000)
        deflate = zipfile.ZipFile(FIXTURES / "ok-deflate.zip")
        self.assertEqual(deflate.testzip(), None)
        self.assertTrue(any(info.compress_type == zipfile.ZIP_DEFLATED for info in deflate.infolist()))
        for info in deflate.infolist():
            self.assertLessEqual(info.file_size, max(info.compress_size, 1) * 100)

        traversal = names((FIXTURES / "traversal.zip").read_bytes())
        for path in ("../evil.json", "/abs.json", "a\\b.json", "foo/../../x.json"):
            self.assertIn(path, traversal)

        duplicate = zipfile.ZipFile(FIXTURES / "duplicate.zip")
        folded = [info.filename.casefold() for info in duplicate.infolist()]
        self.assertGreater(folded.count("content.json"), 1)

        ratio = zipfile.ZipFile(FIXTURES / "ratio.zip")
        pad = ratio.getinfo("assets/pad.bin")
        self.assertGreater(pad.file_size, pad.compress_size * 100)
        self.assertEqual(pad.compress_type, zipfile.ZIP_DEFLATED)

        link = zipfile.ZipFile(FIXTURES / "symlink.zip").getinfo("assets/alias.json")
        self.assertEqual((link.external_attr >> 16) & 0o170000, 0o120000)
        self.assertEqual(zipfile.ZipFile(FIXTURES / "symlink.zip").read("assets/alias.json"), b"content.json")

        with self.assertRaises(zipfile.BadZipFile):
            zipfile.ZipFile(FIXTURES / "corrupt-crc.zip").read("content.json")
        with self.assertRaises(zipfile.BadZipFile):
            zipfile.ZipFile(FIXTURES / "truncated.zip").read("manifest.json")

        mismatch = zipfile.ZipFile(FIXTURES / "hash-mismatch.zip")
        declared = json.loads(mismatch.read("manifest.json"))
        content = next(item for item in declared["files"] if item["path"] == "content.json")
        self.assertNotEqual(hashlib.sha256(mismatch.read("content.json")).hexdigest(), content["sha256"])

        h5 = json.loads(zipfile.ZipFile(FIXTURES / "h5.zip").read("manifest.json"))
        self.assertEqual(h5["kind"], "questify.h5")
        self.assertIn("run.js", names((FIXTURES / "script.zip").read_bytes()))
        secret = zipfile.ZipFile(FIXTURES / "encrypted.zip").getinfo("assets/secret.bin")
        self.assertTrue(secret.flag_bits & 1)
        self.assertIn("assets/only-a.webp", names((FIXTURES / "swap-a.zip").read_bytes()))
        self.assertIn("assets/only-b.webp", names((FIXTURES / "swap-b.zip").read_bytes()))
        self.assertNotIn("assets/only-b.webp", names((FIXTURES / "swap-a.zip").read_bytes()))


if __name__ == "__main__":
    import sys
    if "--write-fixtures" in sys.argv:
        write_fixtures(FIXTURES)
        print(f"wrote {FIXTURES}")
    else:
        unittest.main()

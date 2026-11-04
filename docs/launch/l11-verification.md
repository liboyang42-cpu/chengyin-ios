# L11 verification receipt — 2026-11-04

Status: **PARTIAL / NOT ACCEPTED**. Safe local inspection/launch-denial group
implemented. End-to-end author upload→review→merchant installation→player server
completion remains unimplemented at the frozen backend contract; see
`l11-integration-map.md`. TECHNICAL_READY=false; PUBLIC_RELEASE_ALLOWED=false.

Base: `eec839502b11f1119a6ede212c768bb3f2de4f29`.
Frozen backend: `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
Branch: `codex/l11-package-safety` in public `liboyang42-cpu/chengyin-ios`.

## Implemented behavior

- Original JSON bytes are checked before Foundation decoding loses duplicate-key
  information. Escaped/Unicode keys, nested object scope, strict JSON syntax and
  a technical recursion ceiling are checked. Manifest/content/locale JSON with
  matching ZIP CRCs and matching manifest fingerprints still fails on ambiguity.
  Existing file digest, ZIP limits, cancellation/generation and local-only report
  boundaries remain in place. This is not ServerPlan compilation or review.
- H5LaunchIssuer no longer mints a client UUID or derives the shell origin from
  the API host. Without a real server-issued launch contract it returns
  `serverIssuedLaunchUnavailable` and exposes neither launch nor shell URL.
  Original installation receipt reads remain bound to the same request/identity;
  unknown reads can later recover that original receipt. The installation receipt
  is not an H5 result and no H5 result/attempt is created.

## Actual checks and limits

| Check | Actual result |
| --- | --- |
| Swift 6.2.1, Debian 13, isolated pure Core package, 20 unchanged-or-final production source files | Build succeeded; 32 XCTest tests, 0 failures across H5LaunchIssuer, H5LaunchProducer, H5ShellBinding, H5ShellParentFlow and QmodManifestContract suites. No mocks replaced these production types. |
| Same two security regression tests against original base source | RED: 2 tests, 29 assertion failures (legacy client-ticket issuance and duplicate JSON ambiguity). Tests referencing newly introduced types were excluded from this baseline-only harness. Final production sources pass the full 32 above. |
| Archive compile/runtime portability experiment | 4 selected XCTest tests passed: stored and deflate good packages, duplicate JSON in each manifest/content/locale entry with matching digests, malformed content/recheck/replacement/cancel. This is an adapted Linux harness, **not Apple/Xcode validation**; transformations are listed below. |
| `python3 -m unittest discover -s Tests/ContractChecks -p test_qmod_archive_inspection.py -v` | 8 passed. Fixture/source guards, not Swift execution. |
| `python3 -m unittest discover -s Tests/ContractChecks -p test_reform_world_contracts.py -v` | 8 passed. Source guards, not App acceptance. |
| `python3 -m unittest discover -s Tests/ContractChecks -p test_c10_workshop_h5.py -v` | 11 passed, 2 failed: `test_no_shared_forbidden_owners_or_iap` and `test_sha256_payload_covers_whitelist`. The exact same failures reproduce in a clean archive of base eec8395. PBX already contains WorkshopModuleImportGate; historical hash receipt for untouched H5SessionCapabilityGateTests differs. No pins/assertions were changed. |
| `swiftc -frontend -parse Tests/CoreTests/QmodArchiveInspectionTests.swift Core/QmodArchiveInspection.swift` | Passed syntax parse. This does not establish Apple framework typechecking. |
| `git diff --check` and credential-pattern scan of changed files | Passed; no credential-pattern hits. No private source or raw source-spec documents are included. |

The temporary archive harness replaces Darwin imports/qualified POSIX calls with
Glibc, uses Linux `stat.st_mtim` and explicit Int64 file-size conversions, and uses
a test-only CryptoKit-shaped SHA256 adapter over the system OpenSSL implementation
plus a system zlib module map. Apple's security-scoped URL methods are unavailable;
the harness has a no-op compatibility extension and selects no file-picker or
security-scope tests. The four archive tests are evidence about the archive/JSON
logic only. No portability adapter or dependency is committed to the app.
The first 32-test run used the original pure Core sources without those adapters.
The test ZIP builder was split into typed fields after an initial long Swift
expression typecheck; the final four-test run built and passed in 3.08 seconds.

Swift was downloaded over TLS from the official download.swift.org Swift 6.2.1
Ubuntu 24.04 release. Toolchain signature verification was NOT completed: fetching
the public key from www.swift.org returned HTTP 403; no alternate network route
was used. This limits toolchain provenance assurance, independent of App acceptance.

NOT_RUN: original Darwin/CryptoKit archive XCTest on Apple SDK; full repository
Swift package/Xcode build; UI/real WebKit/malicious pages; simulator/device;
real HTTP server; MySQL/Redis/DDL; real upload/quarantine/scanner; real author,
merchant, player or bilingual journey; mini-program runtime regression; CI;
production, payments or rewards. No server, database, public port or credential
was created, and no CI dispatch, PR or public comment was made.

## Delivery and exact bytes

Batch 1: `0f7ce73c7404314ff62f9f07cdebd4b0c3af2cfa` — qmod safety,
scope receipt and integration map. All six committed files fetched back and
compared byte-for-byte.

Batch 2: `914540f2c83034a12cba304aca2383e468f075fb` — H5 local mint
removal and original receipt recovery regression tests. Both files fetched back
and compared byte-for-byte.

Final evidence batch also includes the typed test ZIP-builder compile fix and
this report. Its commit SHA is recorded by the final delivery response, avoiding
a self-referential report hash. All final changed-file bytes must be fetched back
and compared before declaring the upload successful. The branch is outside all
workflow push filters; commits also carry `[skip ci]`.

One initial create_blob was denied by automatic approval review, saying public
upload authorization was missing. After reading the user's exact prior public
chengyin-ios upload approval and direct-submit instruction, the same action was
retried once and succeeded. No alternate upload tool/path bypass was used.

| Production/test file | Bytes | SHA-256 |
| --- | ---: | --- |
| `Core/QmodManifestContract.swift` | 15771 | `6489945e8a8c46c5ef889c3e2eaeb6a9f6a13da1c072fb2a7dd360d090198f9d` |
| `Core/QmodArchiveInspection.swift` | 49002 | `3a4a75d0ca4ac31eb2155455f9a221254ab70dcd0b90e5ebb05e7a6ba71ee0cb` |
| `Core/H5LaunchIssuer.swift` | 9406 | `7a6e4f29f893d536b39a5e92be4d10c899721b83b715fe9582d9ad93a74c290a` |
| `Tests/CoreTests/QmodManifestContractTests.swift` | 7704 | `f5e9c7ba6b14e334d97e1b1a6ff6e0011333fcc30eaa01ed6daee9d824ab723b` |
| `Tests/CoreTests/QmodArchiveInspectionTests.swift` | 24828 | `44f1db0fc4b42383dc452afab79e048e4395f64de3401271ee647ec90d8754d7` |
| `Tests/CoreTests/H5LaunchIssuerTests.swift` | 12867 | `f0840a25b4bb698bbb078e4858d957c69223ddadb0d38f85ce35758a51a78e43` |

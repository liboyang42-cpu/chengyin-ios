# Gitleaks false-positive audit — 2026-10-02

## Findings and evidence

Reviewed every finding in secrets job `110711635215` for native migration commit
[`e39c367a35e1f15f9553701cbad56d0d10796c80`](https://github.com/liboyang42-cpu/chengyin-ios/commit/e39c367a35e1f15f9553701cbad56d0d10796c80).
Gitleaks **8.24.3** reported **42** `generic-api-key` findings across **13** files:

- **40** stored external-source SHA-256 provenance values in explicitly named hash maps
- **1** native Swift file SHA-256, independently recomputed and matched
- **1** API-route string in an assertion forbidding mutation routes in a read-only service
- **0** credential values identified among these findings

Every referenced line and its surrounding data/code was inspected. All 41 digest
values are lowercase 64-character hexadecimal strings keyed by source-file paths.
The external source is intentionally absent; this review establishes the stored
hashes' evidence role, not a fresh external-source hash or parity verification.
No external source checkout was read or imported. Candidate values are not copied
here; the immutable commit and exact locations below preserve each finding's source.

Line numbers refer to the reviewed commit. Each listed line has its own exact
`commit:path:rule:line` entry in `.gitleaksignore`.

| File | Lines | Count | Classification and context |
| --- | --- | ---: | --- |
| `Tests/ContractChecks/test_account_collection_structure.py` | 18 | 1 | Forbidden-route assertion literal; Read-only service guard |
| `docs/club-governance-static-evidence.json` | 11, 12, 13, 14, 15, 16, 17 | 7 | External-source SHA-256 evidence; `source_hashes` |
| `docs/community-media-templates/packets/native-template-authoring-repair/template-authoring-repair-manifest.json` | 30, 31 | 2 | External-source SHA-256 evidence; `source_sha256` |
| `docs/door-referral-evidence.json` | 11, 12 | 2 | External-source SHA-256 evidence; `source_hashes` |
| `docs/merchant-business-extension-verification.json` | 58, 59, 60, 61 | 4 | External-source SHA-256 evidence; `sourceHashes` |
| `docs/merchant-business-verification.json` | 47, 48, 49, 50, 51, 52, 53, 54, 55, 56 | 10 | External-source SHA-256 evidence; `sourceHashes` |
| `docs/merchant-content-static-evidence.json` | 10, 11, 12, 13, 14, 15, 16 | 7 | External-source SHA-256 evidence; `source_sha256` |
| `docs/official-action-manifest.json` | 60 | 1 | Native-file SHA-256; recomputed and matched; `sha256` |
| `docs/official-action-static-evidence.json` | 11 | 1 | External-source SHA-256 evidence; `source_sha256` |
| `docs/remaining-native-clients/images/packet-manifest.json` | 120, 121, 122 | 3 | External-source SHA-256 evidence; `source_hashes` |
| `docs/settings-native-verification.json` | 10 | 1 | External-source SHA-256 evidence; `sourceSha256` |
| `docs/square-journey-chat/packets/native-square-governance-new/docs/static-evidence.json` | 65 | 1 | External-source SHA-256 evidence; `source_sha256` |
| `docs/template-authoring-validation.json` | 9, 10 | 2 | External-source SHA-256 evidence; `source_sha256` |

The native hash is for `Core/OfficialActionInjectedAccess.swift`. The route finding
is in `test_exact_read_routes_and_no_mutations`, followed by an assertion requiring
the route to be absent from `Core/AccountCollectionService.swift`.
Available generators explicitly call `hashlib.sha256(...read_bytes()).hexdigest()`:
`tools/check_official_actions.py`, `tools/check_door_referral.py`,
`tools/check_merchant_content.py`, `tools/check_club_governance.py`, and the square
packet's `tools/check_square_governance.py`.

## Narrow suppression and full-history gate

The ignore file contains only the **42 exact fingerprints** from that immutable
commit. There are no global fingerprints, path patterns, whole-commit exclusions,
disabled rules, or inline allow comments. Another commit, unlisted location, or
rule remains scanned. Rewritten/squashed history intentionally requires new review.
Do not remove commit prefixes or bulk-refresh this list.

Upstream [8.24.3 documentation](https://github.com/gitleaks/gitleaks/blob/v8.24.3/README.md#gitleaksignore)
and [implementation](https://github.com/gitleaks/gitleaks/blob/v8.24.3/detect/detect.go)
confirm exact fingerprint matching and distinguish commit-bound from global entries.

The pinned action remains the initial scan. Its
[installer](https://github.com/gitleaks/gitleaks-action/blob/e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e/src/gitleaks.js)
adds the installed binary to later steps' PATH via `core.addPath`; `GITLEAKS_VERSION`
explicitly keeps the reviewed **8.24.3** version. The same source limits push/PR
scans to their event range and has no full-history log-options environment override.

An additional shell step reuses that binary and fails if it is missing or a scan
returns nonzero. It runs `gitleaks git --redact --exit-code=2` with
`--log-opts="--full-history -m HEAD"`. With the existing full-depth checkout, this
includes all HEAD-reachable history and merge-parent diffs, while leaving unrelated
branch tips outside the scan. Git's [log documentation](https://git-scm.com/docs/git-log)
defines these revision and merge-diff options. `contents: read`, redaction, disabled
artifact uploads, and disabled comments are preserved. No second download or
additional service access is introduced.

A green successor-only scan cannot close the original findings. The extra gate
must pass on the corrective commit, including the original import in its history.
Additional historical findings require their own review, not a broader exclusion.

## Validation and limits

- PASS: 42 distinct ignore entries exactly match the 42 redacted CI-log fingerprints
- PASS: 41 named hash-map values match SHA-256 format; native digest recomputed
- PASS: 210 negative fingerprint-scope assertions for other commits, paths, rules, unlisted lines, and global forms
- PASS: all five account-collection structure tests, including the flagged assertion
- Local workflow/ignore contract checks are covered by `tools/tests/test_gitleaks_configuration.py`
- Gitleaks execution: **NOT_RUN locally**; the filtered publication tree has no Git metadata and no Gitleaks binary is installed
- Full scanner verification remains the remote CI full-history step; source/contract checks do not substitute for it

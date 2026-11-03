# Gemini Redacted Public Verification Evidence (`ab2d3905ec0b0fb17b58ba6b53ec433d83164701`)

- **Source Repository**: `https://github.com/liboyang42-cpu/chengyin-ios`
- **Evaluated Branch / PR**: `origin/codex/ios-main-integration-20261101` (PR `#126`)
- **Evaluated Commit SHA**: `ab2d3905ec0b0fb17b58ba6b53ec433d83164701`
- **Parent Commit SHA**: `4b1bd1c88fd42177268e50ca58215c3fd79d86c2`
- **Root Git Tree**: `95d4c55b5fd6dd1a76e923c6c076da6c12e0e864`
- **Worktree Dirty State**: `0` (`git status --porcelain --untracked-files=all` empty)

## Redaction Policy
All builds and tests were executed strictly against the public repository `liboyang42-cpu/chengyin-ios` at `ab2d3905ec0b0fb17b58ba6b53ec433d83164701` using synthetic test fixtures (`QUESTIFY_API_BASE_URL` empty, zero live credentials or private repository files).
Before publishing this evidence branch, the following local filesystem path redactions were applied to all text logs and exported `.xcresult` JSONs:
- `/Users/fanning/chengyin-ios-public-20261103` -> `<PUBLIC_REPO_WORKTREE>`
- `/Users/fanning/chengyin-ios-handoff-20261027` -> `<ARTIFACTS_ROOT>`
- `/Users/fanning` -> `<LOCAL_HOME>`

All compiler diagnostics, test suite/method names, assertions, durations, and exit codes are 100% unmodified. Both pre-redaction (`raw_local_bytes`, `raw_local_sha256`) and post-redaction (`redacted_bytes`, `redacted_sha256`, `git_blob_sha1`) values are recorded in `manifest.json`.

## Directory Layout
- `manifest.json`: Complete index of all files, byte sizes, SHA-256 digests, and Git blob SHA-1s.
- `environment/toolchain_and_host.json`: Exact macOS, Xcode, Swift, SDK, and Simulator environment receipt.
- `ledgers/`:
  - `01_core_tests_10841_methods.tsv`: `QuestifyCoreTests` (`10,841 PASS / 0 FAIL`).
  - `04_app_unit_attempt2_no_keychain_5602_methods.tsv`: `QuestifyAppUnitTests` Attempt 2 (`IPHONEOS_DEPLOYMENT_TARGET=17.0`, `CODE_SIGNING_ALLOWED=NO`, before Keychain host entitlement link: `5,561 PASS / 41 FAIL`).
  - `05_app_unit_attempt3_keychain_12suites_123_methods.tsv`: `QuestifyAppUnitTests` Attempt 3 (Keychain-entitled `Questify.app` host, targeted 12 suites / 123 methods: `121 PASS / 2 FAIL`).
  - `15_app_unit_attempt4_full_keychain_host_5602_methods.tsv`: `QuestifyAppUnitTests` Attempt 4 (Keychain-entitled `Questify.app` host, single unmerged full-suite run of all 5,602 methods: `5,597 PASS / 5 FAIL`, `0` Keychain failures).
  - `10_uitests_32_methods_ab2d3905.tsv`: 32 UI test methods executed on `ab2d3905ec` (`13 PASS / 19 FAIL`). Historical run Mach-O UUID provenance on older private SHAs remains `NOT_DETERMINED`.
  - `uitests_all_objc_selectors.txt`: All 1,223 `@objc` test selectors compiled into `QuestifyUITests` on `ab2d3905ec`.
  - `protected-storage-coverage.json` & `protected-storage-summary.md`: 8 physical-device tests (`COMPILED_UNSIGNED_NOT_EXECUTED` / `NOT_RUN_DEVICE_REQUIRED`).
- `xcresult_exports/`: Summary & per-test JSON exports from `xcrun xcresulttool get test-results` plus the exported failure AX hierarchy sample (`UITests-32Provenance-welcome-ax-hierarchy.txt`).
- `logs/`: Full redacted raw logs (`00_tooling_unittests.log` through `15_app_unit_full_keychain_host.log`).

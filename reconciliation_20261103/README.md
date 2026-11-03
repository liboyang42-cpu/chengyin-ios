# Additive Reconciliation & Verification Supplement (`reconciliation_20261103`)

This directory contains **additive** reconciliation artifacts addressing `dot`'s audit items in `liboyang42-cpu/chengyin-app#575` (`#issuecomment-6607059473`, `#issuecomment-6607088419`, `#issuecomment-6607149793`, `#issuecomment-6607620797`, `#issuecomment-6607699160`, `#issuecomment-6607982199`, `#issuecomment-6608417168`).

Per audit rules, **no existing files from prior commits (`25cf3e0be6fd2e0dff18ef2b8003406e6bc33dbd` and `251bb533d1480bcda6ba62fbbf4e507a7de6e756`) were overwritten or deleted**.

## Contents
1. `source_and_version_proof.json`:
   - Exact checkout proof (`git rev-parse HEAD HEAD^{tree} HEAD^` -> `ab2d3905ec0b0fb17b58ba6b53ec433d83164701`, `1256f3ff67514b04cd783b5e72b843de55fc6f53`, `671f9700dea33618b18569f51b7fef84b268dc24`), `.git/logs/HEAD`, `stat -x .git/HEAD`, and `python3 -B tools/current_ci.py check` output (`6,615` sources verified).
   - Verbatim outputs of `sw_vers`, `xcodebuild -version`, `swift --version`, `uname -m`, and `xcrun simctl list devices booted`, plus build-log compiler proof (`macOS 27.0 26A428`, `Xcode 27.1 27A9275`, `swiftlang-6.4.0.34.1 clang-2100.3.34.1`).
   - Exact remote branch heads for all 25 `codex/ui-public-20261103-*` branches (including corrected `P02`, `T01`, `M02`, `CL02`, and absent `G07`, `M01`, `M07`).
   - Explicit confirmation of zero file occupation by Gemini (`dirty = 0`).
2. `contract_checks_reconciliation.json`, `../ledgers/16_contract_checks_5347_methods_reconciled.tsv`, and `../ledgers/16_contract_checks_381_failures_and_errors_detail.tsv`:
   - Full 5,347-row `startTest` ledger (`4,934 PASSED / 277 FAILED / 89 ERROR / 47 SKIPPED = 5,347`) and 381-row outer failure/error detail ledger (`282 FAIL + 99 ERROR`), reconciling the 15 methods missed by the original single-line regex and the `subTest` / `setUpClass` counters in `FAILED (failures=282, errors=99, skipped=48)`.
3. `app_unit_attempt4_5_failures_analysis.md` & `candidate_minimal_fixes.json`:
   - Code-level root cause analysis of all 5 `QuestifyAppUnitTests` failures in Attempt 4 (`15_app_unit_full_keychain_host.log`), plus exact unified diffs, before/after SHA-256s, and verification commands.
4. `xcresult_bundles_inventory.json` & `xcresult_32provenance_attachments/`:
   - Complete inventory of local `.xcresult` bundles (byte counts + SHA-256) and all 19 lossless failure-state PNG screenshots exported from `UITests-32Provenance.xcresult` on `ab2d3905ec0b0fb17b58ba6b53ec433d83164701`.

# Batch 1 & Inventory Correction Addendum (Response to `#issuecomment-6623429218`)

This additive document records the 4 ledger clarifications requested in `liboyang42-cpu/chengyin-app#575` (`#issuecomment-6623429218`) without overwriting or rewriting any existing commits or files on `refs/heads/evidence/gemini-ab2d3905-20261103`.

## 1. Reclassification of the 7 Unreceived UI Patches (`PENDING_RECEIPT / UNCOVERED / NOT_RUN`)

In `screenshot_pilot_batch1_g05_m04_cl02/full_codex_ui_inventory.json`, the 7 unreceived UI patches were previously grouped under `excluded_unreceived_ui_patches` (`EXCLUDED_UNRECEIVED_UI_PATCH`). Per `#issuecomment-6623429218`, they are **never excluded from audit scope**; in `screenshot_audit_batch2_wanted_28/full_codex_ui_inventory_v2.json` they are now classified under `pending_receipt_unreceived_ui_patches` with status **`PENDING_RECEIPT / UNCOVERED / NOT_RUN`** (`待接收 / 未覆盖 / NOT_RUN`):

| Scope Code | Domain | Current Inventory Status | Missing Code Bytes / Branch Provenance |
|---|---|---|---|
| `P02` | Personal / Profile UI | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Missing patch bytes in local/public git object store |
| `T01` | Ticket / Order UI | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Missing patch bytes in local/public git object store |
| `G07` | Game / Play Route UI | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Missing patch bytes in local/public git object store |
| `M01` | Merchant UI | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Missing patch bytes in local/public git object store |
| `M07` | Merchant UI | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Missing patch bytes in local/public git object store |
| `M02` | Merchant UI | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Missing patch bytes in local/public git object store |
| `CL02` (later 11-file / 21,282B batch) | Club UI (later 11-file / 21,282B patch) | `PENDING_RECEIPT / UNCOVERED / NOT_RUN` | Base `CL02` (`1bd53cd1`) is covered in Batch 1; later 11-file / `21,282`B batch is pending code-bytes receipt |

## 2. Local Mac Execution Provenance vs `tools/current_ui_pilot.py` `guard_context()` Placeholders

All Batch 1 (`screenshot_pilot_batch1_g05_m04_cl02/`) and Batch 2 (`screenshot_audit_batch2_wanted_28/`) executions ran on **local macOS (`Xcode 27.1 / 17B100`, `iPhone 17 Pro` simulator `UDID 04862958-4962-4C9C-8359-16072576AE66`, `iOS 27.0 / 23A344`)** and **never triggered GitHub Actions CI**.

Why `pilot-manifest.json`, `attempt1_unmodified_57a62ae4_manifest.json`, and `attempt2_a7ff3b19_manifest.json` contain `trigger.event="push"`, `run_id="1"`, `attempt="1"`, and `run_url="https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/1"`:
- `tools/current_ui_pilot.py` enforces `guard_context()`, which checks `GITHUB_EVENT_NAME in {"push", "workflow_dispatch"}`, `GITHUB_REF_NAME == "screenshot/codex-ui-20261103"`, and constructs `run_url` from `GITHUB_SERVER_URL`, `GITHUB_REPOSITORY`, `GITHUB_RUN_ID`, and `GITHUB_RUN_ATTEMPT`.
- To run `tools/current_ui_pilot.py` unmodified on local Mac without touching GitHub Actions, those environment variables were supplied locally as synthetic placeholders (`GITHUB_EVENT_NAME=push`, `GITHUB_RUN_ID=1`, `GITHUB_RUN_ATTEMPT=1`). They are **not** real GitHub Actions run IDs or URLs.

| Batch 1 Attempt | Local Worktree Commit | Local Worktree Tree | Exact Local Execution Outcome & Preserved Log Path |
|---|---|---|---|
| **Attempt 1** (Unmodified `57a62ae4`) | `57a62ae40f6f83ec4a95db6c4bf3fae1ba13cd60` | `781f9566e22699081b7667dbff94d90878a53f6e` | Failed `build-for-testing` (`returncode=65`) due to `Vendor/GLTFKit2` `IPHONEOS_DEPLOYMENT_TARGET = 12.1 < 15.0`. Log: `screenshot_pilot_batch1_g05_m04_cl02/logs/attempt1_unmodified_57a62ae4_build-for-testing.stdout.txt` |
| **Attempt 2** (`57a62ae4` + 921B `Vendor/GLTFKit2` deployment target fix) | `a7ff3b19c5303f25b37fc677e87fa1941289b555` | `f82f4e93db148cc50013830a00fb0834124dc1b2` | Passed `build-for-testing`; failed `test-without-building` (`returncode=124`, 0/6 passed) due to iOS 27.0 `.toolbar` zero-height screenshot helper + `ToolbarOverflowBarButtonItem` hiding `club.ops.writeCount`. Log: `screenshot_pilot_batch1_g05_m04_cl02/logs/attempt2_a7ff3b19_test-without-building.stdout.txt` |
| **Attempt 3** (`a7ff3b19` + 2-file test-helper compatibility diff) | `ac6f18a35cdc63c1a20b54a9596671c76549567c` | `22857935d8859593ecb8cb49d736b902d7b7a3e6` | Passed `build-for-testing` & `test-without-building` (`PILOT_EXIT_CODE=0`, 6/6 methods passed, 17/17 PNGs exported). Log: `screenshot_pilot_batch1_g05_m04_cl02/logs/attempt3_ac6f18a3_test-without-building.stdout.txt` |

## 3. Exact 40-Char Git Blob SHAs for the 2 Test-Helper Files (`ac6f18a3`)

In `#issuecomment-6623374010`, the 8-char `git diff` header prefixes (`36b25bf2` and `c65e6b90`) were manually mistyped when expanded to 40 chars in the comment prose. The exact verified 40-char Git blob SHAs (matching `pilot-manifest.json` and `pilot_ui_test_ios27_compatibility.diff`) are:

| File Path | Base `57a62ae4` Git Blob (40-char) | Patched `ac6f18a3` Git Blob (40-char) | Exact Bytes | Patched SHA-256 |
|---|---|---|---|---|
| `Tests/AppUITests/ClubProfileScopeFlowTests.swift` | `df1f536e22bc48ccfc205ec5da73943c323dfca4` | `36b25bf28a9f71e4d3d77bb76066b73d9b52b90e` | `11,312` | `50c5934558144015437dafee3cc62558bb95d8ef85a0209a456ee17133664a34` |
| `Tests/AppUITests/FailureScreenshot.swift` | `2ba92241595005a776810d5d4368352052ba34be` | `c65e6b903ab3dc0c836995de380226a67141cc46` | `9,953` | `5046ee70cc77424d2d24e8ae4c9cac7047d1a9b689a194f63e82d7fb41889224` |

## 4. `ClubProfileScopeFlowTests.visibleWriteCounters` Non-Hittable Fallback Status

- **Status**: **Test-helper candidate pending code-line semantic review** (`待代码线语义复核的测试辅助候选`).
- **Context & Semantic Preservation**: On iOS 27.0 (`23A344`), SwiftUI `.toolbar` places `club.ops.writeCount` inside `_UIButtonBarButton` / `ToolbarOverflowBarButtonItem`, which reports `isHittable == false` while still exposing the live accessibility `identifier` (`club.ops.writeCount`), `value` (`account=701;finished=0`), and `label` (`0`). The fallback in `visibleWriteCounters(in:accountID:)` only activates when `hittable.isEmpty` and still strictly enforces:
  1. Current account scope identity (`value.hasPrefix("account=\(accountID);")`),
  2. Uniqueness (`XCTAssertEqual(counters.count, 1)`), and
  3. Zero-write assertion (`XCTAssertEqual(counters[0].label, "0")`).

# Provenance, Summary Ledger, & Source Attribution Correction (per `#issuecomment-6625719721`)

- **In Response To**: [`liboyang42-cpu/chengyin-app#575` `#issuecomment-6625719721`](https://github.com/liboyang42-cpu/chengyin-app/issues/575#issuecomment-6625719721)
- **Previous Evidence Commit Preserved Untouched**: `1f1bb263a6eff7f53f99e8359c2b40bb2e1f7b5e` (Root Tree `e43a6f8359d894b502857427ed5925cdc7ead1fe`)
- **Candidate Commit Under Verification**: `c924bebf4d23c8abc99d9925cc8240352a641c46` (Root Tree `8c503bf6cdd0884c6c95bc7fe620da95b418c5f9`, Parent `ac6f18a35cdc63c1a20b54a9596671c76549567c`, Baseline `ab2d3905ec0b0fb17b58ba6b53ec433d83164701`, `dirty_files_count = 0`)

---

## 1. Corrected 6-Batch Execution & Raw PNG Byte Ledger

Per raw `summary.json`, `test.stdout`, and Git tree PNG byte sizes across all 6 evidence directories:

| Batch / Directory | Target Method Executions (`P / F`) | Exported PNG Count | Raw PNG Bytes Sum | Visual Audit Verdict Breakdown (per Manifest) |
|---|---:|---:|---:|---|
| **Batch 1** (`screenshot_pilot_batch1_g05_m04_cl02/`) | `6P / 0F` (6 unique methods) | `17` | `5,282,753` | `5 PASS / 12 ISSUE_FOUND` |
| **Batch 2** (`screenshot_audit_batch2_wanted_28/`) | **`22P / 1F`** (23 unique methods; failed: `AccessibilityPresentationFlowTests/testRouteMapChineseDarkLargeTextMarksPreviewedPinAndKeepsEquivalentList`) | `28` | `7,188,546` | `18 PASS / 10 ISSUE_FOUND` |
| **Batch 3A** (`screenshot_audit_batch3a_25methods/`) | `19P / 6F` (25 unique methods) | `29` | `7,085,563` | **`20 PASS / 3 ISSUE_FOUND / 6 TEST_FAILURE_SCREENSHOT`** |
| **Batch 3B** (`screenshot_audit_batch3b_25methods/`) | `22P / 3F` (25 unique methods) | `26` | **`9,618,807`** | **`11 PASS / 12 ISSUE_FOUND / 3 TEST_FAILURE_SCREENSHOT`** |
| **Batch 3C** (`screenshot_audit_batch3c_25methods/`) | `24P / 1F` (25 unique methods) | `36` | `12,711,831` | `23 PASS / 12 ISSUE_FOUND / 1 TEST_FAILURE_SCREENSHOT` |
| **Post-fix `c924bebf`** (`screenshot_remediation_c924bebf_7patches/`) | `15P / 0F` (15 targeted re-executions of `G05`/`M04`/`CL02`/`D01`/`S01`/`B01`/`T02` methods) | `27` | **`7,202,547`** | **`23 PASS / 4 PASS_WITH_MINOR_SCROLL_NOTE`** |
| **Cumulative Total** | **`119` method executions (`108P / 11F`)** *(104 unique baseline methods: `93P / 11F`; + 15 targeted post-fix re-executions: `15P / 0F`)* | **`163`** | **`49,090,047`** | Baseline 136 PNGs: `77 PASS / 49 ISSUE_FOUND / 10 TEST_FAILURE_SCREENSHOT`; Post-fix 27 PNGs: `23 PASS / 4 PASS_WITH_MINOR_SCROLL_NOTE` |

### Scope & Unreceived Patch Ledger Notes
- **Bucket 3 (`Batch 3A + 3B + 3C`)**: All 75 methods in the Bucket 3 manifest have been executed (`65P / 10F`). This represents completion of the 75-method test list execution, **not** full-App acceptance completion.
- **7 Unreceived UI Items Remain `PENDING_RECEIPT / UNCOVERED / NOT_RUN`**: `P02`, `T01`, `G07`, `M01`, `M07`, `M02`, and the later 11-file (`21,282` B) `CL02` batch remain strictly classified as `PENDING_RECEIPT / UNCOVERED / NOT_RUN` and are never conflated with the 7 owner fix patches (`G05`, `M04`, `CL02` 2-file picker/choice subset, `D01`, `S01`, `B01`, `T02`) verified on `c924bebf4d23c8abc99d9925cc8240352a641c46`.
- **`B02` (non-cash benefits) and `G08` (map fix)**: Neither `B02` nor `G08` is part of the 15 post-fix methods executed on `c924bebf4d23c8abc99d9925cc8240352a641c46`.

---

## 2. Patch-by-Patch Unit Clarification (Test Methods vs. Exported PNGs on `c924bebf`)

| Patch Group | Target Test Methods Executed (`P / F`) | Exported PNGs | Verdict Breakdown (PNG Units) |
|---|---:|---:|---|
| **`G05`** | `1` method (`1P / 0F`: `TeamFlowTests/testCreatePrivateTeamReviewCancelPreservesForm`) | `6` PNGs | `3 PASS`, `3 PASS_WITH_MINOR_SCROLL_NOTE` (`#21`, `#23`, `#25`) |
| **`M04`** | `1` method (`1P / 0F`: `MerchantRegistrationAvailabilityFlowTests/testCancelAndRestorePreserveOriginalUnrecognizedSource`) | `4` PNGs | `3 PASS`, `1 PASS_WITH_MINOR_SCROLL_NOTE` (`#13`) |
| **`CL02`** | `4` methods (`4P / 0F`: `ClubProfileScopeFlowTests/testCaptureCL02TypeChoiceSheetWithoutApplying`, `testCaptureCL02DirectionsSheetWithoutApplying`, `testCaptureCL02ProfileReviewWithoutSubmitting`, `ClubGovernanceFlowTests/testCaptureCL02RolePickerWithoutPreparing`) | `7` PNGs | `7 PASS`, `0 PASS_WITH_MINOR_SCROLL_NOTE` |
| **`D01`** | `4` methods (`4P / 0F`: `HomeFeedFlowTests/testTypedDestinationsAndPriceCurrencyDisclosure`, `testEmptyStateIsNotAnError`, `testPageFailureRetriesAndDuplicateFullPageStillPaginates`, `AccessibilityPresentationFlowTests/testHomeChineseDarkLargeTextRemainsNavigable`) | `4` PNGs | `4 PASS`, `0 PASS_WITH_MINOR_SCROLL_NOTE` |
| **`S01`** | `2` methods (`2P / 0F`: `ReferenceChatTaskFlowTests/testMessageKeyboardKeepsSendActionReachable`, `testMessageEarlierPageAndDetailReturnRetainHistory`) | `3` PNGs | `3 PASS`, `0 PASS_WITH_MINOR_SCROLL_NOTE` |
| **`B01`** | `1` method (`1P / 0F`: `ModuleFlowTests/testProfileOrderReadbackAndBack`) | `1` PNG | `1 PASS`, `0 PASS_WITH_MINOR_SCROLL_NOTE` |
| **`T02`** | `2` methods (`2P / 0F`: `TemplateOwnShelfFlowTests/testOwnedCardShowsZeroDurationAndNoMarketplacePublishButton`, `testDeleteReviewShowsSourceDangerCopyAndCancelDoesNotSubmit`) | `2` PNGs | `2 PASS`, `0 PASS_WITH_MINOR_SCROLL_NOTE` |
| **Total** | **`15` methods (`15P / 0F`)** | **`27` PNGs** | **`23 PASS`, `4 PASS_WITH_MINOR_SCROLL_NOTE`** *(4 PNGs carry scroll/sticky-header notes; not 27 unconditional visual passes)* |

---

## 3. Resolution of the 7-Patch File & Git Blob Attribution Conflict

### Root Cause of Narrative Attribution Conflict in v1
- The worktree compiled at `2026-11-04T15:32:07+08:00` and tested at `2026-11-04T15:42:29+08:00` was cleanly checked out at **`HEAD = c924bebf4d23c8abc99d9925cc8240352a641c46`** (`tree = 8c503bf6cdd0884c6c95bc7fe620da95b418c5f9`, `parent = ac6f18a35cdc63c1a20b54a9596671c76549567c`, `git status --short` = empty / `dirty = 0`).
- In the v1 packaging script (`remediation-c924bebf-manifest.json` and `#issuecomment-6625565892`), the `verdicts` dictionary contained hand-typed placeholder file names (`App/HomeFeedModuleView.swift`, `App/ClubProfileScopeView.swift`, `App/ClubGovernanceView.swift`, `App/ReferenceChatTaskView.swift`, `App/OrderModuleViews.swift`, `App/TemplateOwnShelfView.swift`, `App/TeamModuleView.swift`, `App/MerchantContentView.swift`) and unverified 8-character short prefixes instead of reading `seven_owner_patches_ack_6624585230.json` or `git diff --raw ac6f18a3 c924bebf`. None of those `*ModuleView.swift` paths exist in tree `8c503bf6cdd0884c6c95bc7fe620da95b418c5f9`.
- Below is the exact, verified `git diff --raw ac6f18a35cdc63c1a20b54a9596671c76549567c c924bebf4d23c8abc99d9925cc8240352a641c46` table from the tested worktree, junto with the unchanged test/caller files in `8c503bf6cdd0884c6c95bc7fe620da95b418c5f9`:

| Group | Actual Modified File in `c924bebf` (`git diff --raw ac6f18a3..c924bebf`) | Baseline `ab2d3905` Blob | Parent `ac6f18a3` Blob | Tested `c924bebf` After Blob | Unchanged Test / Host Files in `c924bebf` Tree (`8c503bf6`) |
|---|---|---|---|---|---|
| **G05** | `App/TeamComponents.swift` | `7d4ae7f6605f41c6cd2a66f262f8a854b2e791c4` | `7d4ae7f6605f41c6cd2a66f262f8a854b2e791c4` | **`36f2fc3982bc8f7016cf62db3060ed1ea3f3a182`** | `Tests/AppUITests/TeamFlowTests.swift` (`c9107b79a0d004bc47f451029a5fa0bd6f32dc2b`) |
| **M04** | `App/MerchantRegistrationAvailabilityPicker.swift` | `26b77749df20d08493f5fdc80487f15b42cb8939` | `d1bb6f98444a147a420159fc6767df1130691ee5` | **`ac36998a9d2f63cc30b9178f6d0a94c6b8e99da7`** | `App/MerchantContentViews.swift` (`0419a3a0909917f54e20cac862a942fe6f6d4a39`) |
| **M04** | `Tests/AppUITests/MerchantRegistrationAvailabilityFlowTests.swift` | `4487b33a0b943cdac92ddb512c910b84d77da89d` | `c1cc00c794b48bd35fe26738bffe7ef4d0effa6e` | **`0a0e571f8b185d98fa2ef5cec0a79d2b56a7479e`** | *(test file itself modified in `M04`)* |
| **CL02** | `App/ClubProfileChoiceEditor.swift` | `3c8aed56680249925ee79bb639dafe13965beb78` | `3032bf2705476861af055215737059a94dcfc98c` | **`2ac8c61f4f375b4f402b0b428a1b557be787b2d2`** | `Tests/AppUITests/ClubProfileScopeFlowTests.swift` (`9b070604bf5f7848ca2503e6b3f0b613be702f2f`) |
| **CL02** | `App/ClubRoleAssignmentPicker.swift` | `16a70dc37cea647a765a2d6ced2ae7ebbd6e3bbf` | `3d24afd4d2365f41d3fb681204d5b07ab29563e3` | **`3f5bab17dc322b9d72c17be02f25c38343f93792`** | `Tests/AppUITests/ClubGovernanceFlowTests.swift` (`5f0888565d784f53b959a24c2a3c29fb92a6a694`) |
| **D01** | `App/HomeFeedView.swift` | `c6839bfc4b8e4f54f42a7315d7a7add06726741e` | `c6839bfc4b8e4f54f42a7315d7a7add06726741e` | **`05fb5ad98134a621d1f9b00490799461edc77768`** | `Tests/AppUITests/HomeFeedFlowTests.swift` (`64ff51926380a756c00383a558c4489019a0dc23`), `Tests/AppUITests/AccessibilityPresentationFlowTests.swift` (`7a2a6be7ca7fc6a26ee89bfdf58e1f0ef4cb8a01`) |
| **S01** | `App/MessageActionComposer.swift` | `9f6a165ffcca151d17a93f5d9330caf7f0760ee1` | `9f6a165ffcca151d17a93f5d9330caf7f0760ee1` | **`964d7f1f95f6c6579d7f89cfd826993140bdf27d`** | `Tests/AppUITests/ReferenceChatTaskFlowTests.swift` (`c779bf6922de0ee6b5a6b4a849cf06edd0ea1848`) |
| **B01** | `App/ProfileOrderNumberCopySection.swift` | `4b080c78deb70e33b9121b439a8f576a2bb2de3e` | `4b080c78deb70e33b9121b439a8f576a2bb2de3e` | **`97e987947176cd6d7aa2a870d869f8c55277be8d`** | `Tests/AppUITests/ModuleFlowTests.swift` (`15d98b9374e22b2c1c0cb287fa03b3d629c4d55e`) |
| **B01** | `App/ProfileOrdersView.swift` | `3dd785f704cb93c01bae042b6fa75f4041acddd3` | `3dd785f704cb93c01bae042b6fa75f4041acddd3` | **`7c9b5f2d9119c85b7e33c0438ec125118d3b4c9d`** | `Tests/AppUITests/ModuleFlowTests.swift` (`15d98b9374e22b2c1c0cb287fa03b3d629c4d55e`) |
| **T02** | `App/TemplateAuthoringMineView.swift` | `75087810b25e6f143b9167df58a23c244811fd0b` | `75087810b25e6f143b9167df58a23c244811fd0b` | **`6cfd84f775680ff08233cb02d20ed8c50d645602`** | `Tests/AppUITests/TemplateOwnShelfFlowTests.swift` (`8d90a41b73e7f519f1bd13b22d620b47ac515a7d`) |
| **T02** | `App/TemplateOwnShelfCardSection.swift` | `5f38ddcfffc2b4ebb330224093f25253745123e5` | `5f38ddcfffc2b4ebb330224093f25253745123e5` | **`251697242cdb838af11b94446f8b55a9faaa44c5`** | `Tests/AppUITests/TemplateOwnShelfFlowTests.swift` (`8d90a41b73e7f519f1bd13b22d620b47ac515a7d`) |

---

## 4. Build Log, `.xctestrun` Product, `.xcresult` Archive, Toolchain Outputs, & M04 Extra Probe Status

1. **Build Log & `.xctestrun` Product (`REMEDIATION_BUILD_EXIT_CODE = 0`)**:
   - **Build Command**:
     ```
     /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Questify.xcodeproj -scheme Questify -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=25316F87-058C-46CE-8825-617906638207" -destination-timeout 60 -derivedDataPath <RUNNER_TEMP>/remediation-c924bebf-derived-data CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build-for-testing
     ```
   - **Build Completion & Exit Code**: `** TEST BUILD SUCCEEDED **`, exit code `0`, completed at `2026-11-04T15:32:07.903+08:00` (`mtime = 1793777527.9034982`).
   - **Sanitized Build Log**: [`logs/remediation_c924bebf_build_for_testing.stdout.txt`](logs/remediation_c924bebf_build_for_testing.stdout.txt) (`1,665,046` bytes after path redaction from `2,148,253` raw bytes, `15,727` lines, SHA-256 `8d0a6f7b2d68eb6561852487257d3aace113db86e39c730b5cd7a5efa10d257a`, Git blob `e7d11f4ac34f673cbb27683b82e3317e6b725471`).
   - **Generated `.xctestrun` Product Used by `test-without-building`**: [`logs/remediation_c924bebf_xctestrun_product.plist.txt`](logs/remediation_c924bebf_xctestrun_product.plist.txt) (`Questify_iphonesimulator27.1-arm64.xctestrun`, `5,218` bytes, `mtime = 1793777527.8322816` / `2026-11-04T15:32:07.832+08:00`, SHA-256 `d90ec167a514b820a478061c87b3fbbf796a7ab5c4f2144bd03338a48f024d65`, Git blob `135be69e2873a079653fe1e30bee7a2800f08897`).
   - **Toolchain Outputs Bound to This Build**:
     - `xcodebuild -version`: `Xcode 27.1` / `Build version 27A9275`
     - `xcrun swift -version`: `swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)` / `Target: arm64-apple-macosx27.0.0`
     - `xcrun --sdk iphonesimulator --show-sdk-version`: `27.1` (`iphonesimulator27.1`)
     - `xcrun --sdk iphonesimulator --show-sdk-build-version`: `24A94232`
     - *(Note: v1 `remediation-c924bebf-manifest.json` and `batch3b-manifest.json` had a hardcoded placeholder string `Swift 6.3 / 24B74`; corrected in [`remediation-c924bebf-manifest-v2.json`](remediation-c924bebf-manifest-v2.json) and [`source_identity_and_toolchain_snapshot_c924bebf.json`](source_identity_and_toolchain_snapshot_c924bebf.json)).*
2. **Source Identity Snapshot at Build/Test Time**:
   - [`source_identity_and_toolchain_snapshot_c924bebf.json`](source_identity_and_toolchain_snapshot_c924bebf.json) (`13,951` bytes, SHA-256 `8af7d334cdb83ad4b2706d6ff8ea93fe7fd2534588c7423415b5fbfdb1f908a8`, Git blob `0d070529a4f005b4e7ea9539debd0383b16402ae`).
3. **Raw `.xcresult` Archive for the 15-Method Post-Fix Run (`REMEDIATION_15_TEST_EXIT_CODE = 0`)**:
   - **Archive File**: [`remediation_c924bebf_15_methods_ui.xcresult.tar.gz`](remediation_c924bebf_15_methods_ui.xcresult.tar.gz)
   - **File Size**: `10,102,030` bytes
   - **SHA-256**: `e061032db215fcca410426dd4d7b5c80bc341eedb592a4d947f9c2528585b06d`
   - **Git Blob SHA**: `acdba52d23aa51b43e9f0ee9bcd8db6953908f51`
   - **Corresponding Test Run & Manifest**: Bound to [`logs/remediation_c924bebf_15_methods_test.stdout.txt`](logs/remediation_c924bebf_15_methods_test.stdout.txt) (`mtime = 2026-11-04T15:42:29.002+08:00`), [`summary.json`](summary.json), [`tests.json`](tests.json), [`remediation-c924bebf-manifest.json`](remediation-c924bebf-manifest.json), and [`remediation-c924bebf-manifest-v2.json`](remediation-c924bebf-manifest-v2.json) (`51,226` bytes, SHA-256 `fecdd81018cbb02cf4da7a20d34f4bdc7d9bb8879d67f971047b96ffe411c4dd`, Git blob `2401dc908d973fb191fe9942bd397956d7ceb9cb`).
4. **M04 Extra Probe (`testGroupReviewCancelAndExistingSaveReadBackServerValues`) Status**:
   - **Status**: **`未保留 / 无法核实` (`RAW_LOG_OVERWRITTEN_NOT_PRESERVED`)**.
   - **Explanation**: The intermediate probe (`step 1869` / `task-1871` at `~15:35+08:00`) wrote to the same `<RUNNER_TEMP>/remediation-c924bebf-audit/test.stdout` and `<RUNNER_TEMP>/remediation-c924bebf-audit/ui.xcresult` paths that were subsequently `shutil.rmtree`d and overwritten when running the 15-method suite (`step 1920` / `task-1921` at `15:42+08:00`). Because its raw `test.stdout` and `ui.xcresult` were overwritten and not separately archived, it cannot be independently verified from preserved raw files, and per instruction we did not re-run it or execute any `maximumSwipes: 10` change.

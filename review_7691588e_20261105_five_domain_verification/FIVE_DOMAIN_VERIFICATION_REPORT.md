# Five-Domain (`玩家 / 商家 / 俱乐部 / 游戏上传 / 大富翁`) Runtime, Unit & UI E2E Verification Report

- **Review Snapshot Commit (`BASE`)**: `7691588efe5f66c32af5001ebcb6bd3b3de49d05` (`codex/claude-review-61cfe710-20261104`, root tree `f381e903f87ea5bec76565ec295d35644ad66454`)
- **Baseline Parent Commit**: `ab2d3905ec0b0fb17b58ba6b53ec433d83164701` (root tree `1256f3ff67514b04cd783b5e72b843de55fc6f53`)
- **Clean Review Snapshot Worktree Invariant**: `dirty = 0`
- **Clarification on `#issuecomment-6638465582` §1 Table Digests**: In commit `956b7b67a1784116ba6fd1ee31e0a4c2e6ca9402`, `build_and_contract_audit_manifest.json` recorded the exact post-sanitization SHA-256 digests for `01_unmodified_build_for_testing_AppUnitTests.stdout.txt` (`8d1ff826386e5e840c019b0a92eb808fe08cdbd82601f047b5aeca3fadf584d0`, `2,598,323` B) and `02_unmodified_build_for_testing_UITests.stdout.txt` (`f7225a8b0e0f681f827245b23c10869a71d92dafbd3a9101218b84b16ec957b6`, `2,914,687` B), whereas the prose table in `#issuecomment-6638465582` §1 inadvertently pasted the pre-sanitization digests.

## 1. Executive Matrix (Unmodified Snapshot vs. Post-Fix Isolated Worktree)

| Verification Suite | Unmodified `7691588e` | Post-Fix (`patches/runtime_and_ui_fixes_7691588e.patch`) | Evidence Log |
| :--- | :--- | :--- | :--- |
| **40 Python Contract Checks** | `38 PASS / 1 FAIL / 1 NOT_RUN` | **`39 PASS / 0 FAIL / 1 NOT_RUN` (`100%` runnable)** | `logs/09_unmodified_40_python_contract_checks.stdout.txt` & `logs/10_postfix_40_python_contract_checks.stdout.txt` |
| **98 Changed `QuestifyCoreTests` Classes (`95` files)** | `FAIL` (Compile `EXIT=1`) | **`1,139 / 1,139 PASS` (`100%`, `2.723s`, `EXIT=0`)** | `logs/11_coretests_98_classes_unmodified.stdout.txt` & `logs/12_coretests_98_classes_postfix.stdout.txt` |
| **57 Changed `QuestifyAppUnitTests` Classes (`54` files)** | `444 / 447 PASS` (`3 FAIL`) | **`447 / 447 PASS` (`100%`, `22.789s`, `EXIT=0`)** | `logs/13_appunit_57_classes_unmodified.stdout.txt` & `logs/14_appunit_57_classes_postfix.stdout.txt` |
| **Full-Target `QuestifyAppUnitTests` (`710` classes, `584` files)** | Blocked by build/signing & 17 failures | **`6,024 / 6,038 PASS` (`99.77%`)** | `logs/15_appunit_full_6038_tests_postfix.stdout.txt` |
| **5-Domain Representative `QuestifyUITests` (`7` suites, `23` tests)** | `18 / 23 PASS` (`5 FAIL`) | **`23 / 23 PASS` (`100%`, `EXIT=0`)** | `logs/16_uitests_five_domains_23_of_23_pass.stdout.txt` |

## 2. Artifacts & SHA-256 Digests

| Relative Path | Size (Bytes) | SHA-256 |
| :--- | ---: | :--- |
| `logs/09_unmodified_40_python_contract_checks.stdout.txt` | `32066` | `7859975d71460014a32cdf893ec15cdb6c40aec28c11e77d4617344a853951e6` |
| `logs/10_postfix_40_python_contract_checks.stdout.txt` | `17737` | `dbcad7064045e0945713d46ebff8309b8550b0646d08a29f7e364499ec3d0675` |
| `logs/11_coretests_98_classes_unmodified.stdout.txt` | `153296` | `8a6fab698c04a59d5fd2b6195c49390e88c77237a85928c9a6d4f094e7b3abcd` |
| `logs/12_coretests_98_classes_postfix.stdout.txt` | `355426` | `754d0040fd858ab789d1667931eefc6536d97a7266c8b4fbc438bbe63e33e0aa` |
| `logs/13_appunit_57_classes_unmodified.stdout.txt` | `195303` | `0825fb031712ea91b617dffddcad8b9ac0925db4082313c5efc88549018a68d0` |
| `logs/14_appunit_57_classes_postfix.stdout.txt` | `240921` | `fb1cd8270e89d1cb95c6cc535724ffc13261e34236760d58fbf1da278a6359a5` |
| `logs/15_appunit_full_6038_tests_postfix.stdout.txt` | `3088103` | `2bbcc2ce13a10c78f98c41fdac0b437449f89cf686333d429e1718141d9d5c94` |
| `logs/16_uitests_five_domains_23_of_23_pass.stdout.txt` | `589093` | `fd6986729fd33264374d2b3d7c1cdbbb512e5ae2fb5122dbb481c089ff47ab12` |
| `patches/runtime_and_ui_fixes_7691588e.patch` | `88370` | `b9f65c730235618ff95a9a173d2721cb5bdddeb0b454d0fa6340c1d0b868979e` |
| `screenshots/domain1_player_profile_draft_review_restore.png` | `452947` | `f8b769a499b9118a793bf3c2d1cd3c385836475e807a7c5a0c9eca951f91a958` |
| `screenshots/domain1_player_profile_draft_review_xxxl_en.png` | `390145` | `c89b90d8c17c0e3221663681ccd346eee140c902decbe5b0bf504e3c5e78eed6` |
| `screenshots/domain1_player_profile_draft_review_xxxl_zh.png` | `416065` | `ae011fb5410b60ee9c684546af0dca03960466358f6412e8b34204a0ce8a7aa1` |
| `screenshots/domain2_merchant_npc_chat_flow.png` | `99427` | `f13801fc15e0c0598a76003710a814118a5d0667d584cbaa054d82212cf9288d` |
| `screenshots/domain2_merchant_ops_marketing_home.png` | `36045` | `6deef7caf3b318fa33afe7d0b0b28af25eaf31e1003dcaf5565ebcd28c2cfcfb` |
| `screenshots/domain3_club_detail_tabs_before_scroll_fix.png` | `217195` | `6fc56d956d0d9ef27630f71fca62f32c4629c073876eb10918475830a919f238` |
| `screenshots/domain4_game_story_template_upload_editor.png` | `350400` | `b903ac3f2c2a5d093ebf69a2c73ae422d4041fa3fb25d141ae0f15168b33f04a` |
| `screenshots/domain4_workshop_creator_pending_review.png` | `291422` | `40ff9d0c4484f28d682957e4475380f949dd56bda758f98c358658189412e125` |
| `screenshots/domain5_monopoly_city_board_game_flow.png` | `200848` | `de278779575f77ed2d69056be3c8ac4e1fd6c407325d281188d310b2d970ab0e` |

# Latest local source checkpoint — 2026-10-02

This document separates historical evidence from newer source changes. The app is not release-ready; unexecuted UI, device/provider, business and visual acceptance remain explicit gates.

The independent final pass ran 414 Python source/contract checks, 24 tooling tests and 14 parser self-tests successfully. Every executed module/source gate and whitespace check returned zero. All six UI shard dry-runs cover 313 authored methods in 56 classes exactly once. Deterministic project/scheme regeneration produced identical bytes. The 12 authored app-unit tests now belong to a dedicated app-hosted target and separate CI job; they were not executed here.

Whole-tree supplementary parsing still returns exit 1 for ten historical diagnostics. It is not a Swift compiler pass. Swift compilation, all Swift/XCTest execution, Xcode builds, simulator/device, accessibility, media/Keychain and deployed backend/provider acceptance are NOT_RUN because this executor has no Apple toolchain.

Source inventory: 2,125 authored Core test methods, 313 UI test methods, 12 app-unit test methods and 5,145 bilingual default-table keys. Counts are not passed tests or migration completion percentages. Production endpoint, provider, SDK, legal, OS and media grants remain off.

Remaining implementation gate: the WeChat native SDK authorization adapter could not be implemented against a verified official interface. The App code-exchange client and callback/session coordinator are implemented. Attested NPC voice limits, authoritative recovery of interrupted uploads, approved live scopes/legal content and Apple validation remain explicit gates; no receipt endpoint or automatic recovery was invented.

At the 02:39 UTC verification checkpoint, the remote branch still pointed to b754aa1 and its older CI did not validate these sources. Publication and new CI results must be checked against the exact commit on `migration/native-ios`; local checks do not establish Apple execution. No main merge, signing, deployment or live business action is part of this checkpoint.

Exact local command exits, raw outputs, source-stability hashes, shard proof and remote observation are in `root-verification-20261002/`. Initial harness invocation errors at 02:25 were corrected with required command arguments and are not represented as code failures or silently relabeled. The fresh 02:39 pass has only the documented whole-parser failure.

## Publication contents

The Git publication preserves all native implementation, configuration, resource, test and tooling files plus source-contract dependencies and module documentation. Backup-only snapshot metadata, redundant historical raw checks, and patch/preimage scratch artifacts are excluded. The latest independent verification evidence is retained in `root-verification-20261002/`; references in older integration reports describe historical local artifacts that are not all part of the published checkout.

## Public-checkout CI preparation

The public checkout does not contain the external Flutter baseline. Source-only comparisons now skip explicitly when the optional baseline is absent; native-local assertions still run. Sixteen mixed tests were split instead of skipped wholesale. A provided but missing/malformed baseline fails. `CHENGYIN_FLUTTER_SOURCE_ROOT` can supply the baseline without copying it into this repository.

Fresh filtered-checkout results on 2026-10-02: 430 contract methods discovered, 393 passed and 37 explicitly skipped; 30 tooling methods passed, including six source-boundary regressions. The original public-checkout run had 414 methods, 377 passed, 19 skipped and 18 errors caused by unavailable external source. These numbers are Python checks only. The earlier 414-pass checkpoint above used the separately available source baseline. A differently named full checkout also passed, after removing a directory-name assumption from one contract suite. Apple compilation and all Swift/XCTest execution still require CI.

## 2026-10-02 05:54 UTC integration checkpoint

CI run 46 on `51da9a092cccf4ac124cd6fa64afccb4a6ac0ce1` executed 2,132 Core Swift tests with zero failures and passed full-HEAD-history secret scanning. Its unsigned simulator app build still failed on a missing dynamic-title argument label; device builds, app-hosted tests and UI shards did not execute. That label is corrected in this new source bundle, which still requires a fresh Apple CI run.

The new bundle also adds the source-backed merchant tonal-discovery and city-node redemption destinations, and wires the bounded cooperation invitation editor, existing merchant marketing surfaces and a nearby location-purpose/configuration gate. These changes provide native code and normal navigation; they do not establish full page parity, visual acceptance, provider readiness or live mutation permission. Production grants remain off. Camera/location/backend actions were not taken by this integration.

Combined public-checkout checks: 449 Python contracts discovered, 411 passed and 38 explicitly skipped external-source comparisons; 33 tooling tests passed; deterministic project/scaffold checks passed. Current authored inventory is 2,156 Core methods, 319 UI methods, 12 app-unit methods and 5,191 bilingual catalog keys. The newly added Swift/UI methods are not yet executed. The earlier 2,132-test CI success cannot be relabeled as success for this newer source bundle.

## 2026-10-02 06:50 UTC integration checkpoint

Verified Apple checkpoint `cbe9f67c6430ce2ec11641d8115e7d4d91f84431`, run 47: 2,156 Core XCTest methods and 12 app-hosted XCTest methods executed with zero failures. Unsigned simulator, device and US-profile builds passed, as did both built-profile metadata checks and full-HEAD-history secret scanning. The six UI jobs failed to compile the shared test target because a test used an unsupported `lastMatch` property. UI methods and visual acceptance are not passed. The query is corrected in the newer sources, with explicit synthetic screenshot captures and earlier test-bundle compilation added; these still need fresh CI.

The new checked-hunk bundle adds the first PlayKit screen packet and its dirty-state fix; participation/completed history; chapter presentation; typed participation ticket context; member-template reads; club enrollment; media/gallery/poster/stamp surfaces; the separately requested dormant bank-withdrawal form/client; and bounded source-backed publishing-V2 contract repair. New source is not proof of complete business/page parity. Player registration modification is deliberately unconnected because the mini-program links across incompatible player/merchant ID domains. Club-owner financial refund, additional creator/rich-editor support and subsequent verification packets are separate follow-ons. Hardware, backend, provider, legal and live financial grants remain off.

Integration review found and corrected a poster double-confirm race: the one-use review is now consumed before asynchronous preflight, with cancellation and write-ahead fences. The publishing-source test was narrowed to its actual factory rather than unrelated later media factories; its default-off assertions remain. The public checkout runs 486 Python contract methods: 447 passed and 39 explicitly skipped external-source comparisons. All 36 tooling tests and 14 parser self-tests passed. Scaffold and deterministic generation passed. The 88 changed Swift files introduce no supplementary parser diagnostics; the same ten historical whole-tree grammar diagnostics remain unsuppressed.

Current authored inventory: 2,304 Core methods, 325 UI methods, 14 app-unit methods and 5,587 bilingual keys. These newer Swift/UI methods have not been executed at this checkpoint. All incoming source overlays were checked against exact preimages and postimages; shared AppSession and play-host hunks were reconciled without replacing other owners' changes. No private backend, mini-program/Flutter source, raw account data, credentials or signing files were copied into this bundle.

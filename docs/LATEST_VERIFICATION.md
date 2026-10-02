# Latest local source checkpoint — 2026-10-02

This is the 2026-10-02 migration source checkpoint, not a release-ready or runtime-verified app.

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

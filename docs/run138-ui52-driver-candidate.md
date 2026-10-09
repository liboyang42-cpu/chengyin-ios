# CI138 UI52 driver candidate: exact-scope transition barriers

## Status and evidence limits

This isolated candidate implements two explicitly approved test-driver changes against commit
4bf6667f8c5d9d2d59a8063d7d54eaef7a338865, published tree 82e9abd1afa6180815ef7ea5ea314d6eb692e036.
It does not establish that either hosted failure is fixed. No Apple compiler, XCUITest or simulator
has run for this candidate. The genuine UI52 artifact diagnosis is retained separately in
triage-marketing-storyback-ci138-20261008.

Marketing's captured menu remained open with Shop insights selected after the Entitlements tap.
That proves the next picker tap was obstructed and the old error-existence check was not a valid
transition signal. It does not distinguish a wrong/global menu target from an unready option or
a persistent native Picker defect.

Story failed only after the second Apply. The immediate Back hit-test sample was false; the later
screenshot and AX dump showed Chapter, the applied image-reference field and the expected Back.
A dismissal-readiness race is likely, but stale-query identity or a durable app/OS hit-testing
problem is not established. The newly inserted barrier will fail with real app hierarchy evidence
if the expected transition does not occur. It does not retry or bypass the problem.

## Exact six-path allowlist

1. Tests/AppUITests/MerchantMarketingUITests.swift
2. Tests/AppUITests/ProjectStoryImageFlowTests.swift
3. tools/run138_ui52_driver_inverse.py
4. Tests/ContractChecks/fixtures/run138_ui52_driver.json
5. Tests/ContractChecks/test_run138_ui52_driver.py
6. docs/run138-ui52-driver-candidate.md

No App/Core implementation, old helper, old data assertion, old hash/contract, duration profile,
runner, workflow or project-file change is included. Root's sixth-batch workspace is untouched.

## The two additions

Marketing changes only testNormalMerchantWorkbenchOpensDormantMarketingInBothLanguages,
immediately after the existing one-shot option tap. One compound five-second predicate requires:
- the selected picker value, or exact composite accessibility label, matches the requested section;
- the picker is hittable;
- the expected navigation title is present;
- no native menu remains.

The existing unavailable-error and no-settlement assertions remain afterward, along with both
languages, no-purchase checks and return-to-entry coverage. The original global/ordinal option
tap is unchanged by this bounded authorization. If it selects the wrong element or does not
complete, this candidate fails at the actual transition rather than silently continuing.

The English composite label “Section, Shop insights” is directly evidenced by UI52. “栏目” is
read from the existing Chinese localization. The predicate also accepts the exact selected
value when the platform exposes it separately. Actual Chinese AX representation remains to be
verified on Apple runtime; there is no permissive substring match.

Story changes only the second Apply-to-back call site. One compound five-second predicate waits
for Story image Close to disappear and the Chapter BackButton to exist, be enabled and hittable.
The original back(app) call then runs unchanged. The first Apply call site, private back helper,
all exact upload counts, restore, stable block IDs/order, byte-exact image references, prepared
readback and no-submission assertions retain their original bytes.

Neither change adds a tap retry, delay/sleep, coordinate fallback, animation bypass, enlarged
existing timeout, weakened assertion or failure-swallowing branch.

## Explicit full-method costs

These are conservative planning additions to retained full-method costs, not measured timings
or hard bounds on remote AX request latency.

- Marketing original effective method: 114.954 seconds.
  New barrier: 5 seconds × 3 section selections × 2 languages = 30 seconds.
  Candidate complete method: 144.954 seconds.
  Original whole class: 408.399 seconds; candidate whole class: 438.399 seconds.
- StoryImage original complete-method allowance: 900 seconds.
  New second-Apply barrier: 5 seconds × 1 = 5 seconds.
  Candidate complete method / class: 905 seconds.

The exact-current-source 905-second exception was explicitly approved for review. The old
900-second allowance is retained untouched. Failed prefixes (55.197/167.767 seconds) are not
successful full-method observations and are not used to reduce any cost.

This packet contributes +35 seconds. The separate editor-readiness package contributes +160.
The unified current-source layer must validate the complete combined +195 seconds and rerun
whole-method/class inventory and fresh shard grouping with unchanged deadline/startup reserve.
Adding two independently computed budgets is not evidence that the combined schedule fits.

## Strict inverse and integration handoff

The new source fixture stores exact before/after spans and whole-file SHA-256 for only the two
modified UI files. The inverse module pins that fixture by SHA-256, requires the known complete
postimage, rejects missing/duplicate spans, performs the exact inverse, and verifies the complete
published preimage. Unknown paths or source bytes fail closed. Existing helper/source/profile/
guard/workflow hashes are protected. The 12 new tests include negative mutations.

API for the unified planning owner:
- original_source(relative, raw, root) returns a published preimage only for the exact two
  approved current files. Call it only for files owned by this layer.
- validate_costs(root) validates +30/+5 and the explicit 905 method identity.
- validate_current(root) validates this isolated packet's entire baseline UI inventory and
  protected files. It deliberately does not accept another repair package's modified files.

The unified owner must validate its complete combined current inventory, compose all approved
inverses, and then run unchanged historical guards against exact restored source. Do not point
the historical guards at altered current files or relax their original hash/assertion checks.
A combined-source validator must incorporate this layer's postimages and exact cost identities;
the isolated validator is not itself a combined-plan or active-CI adapter.

The current unadapted historical guard will reject this candidate as designed. Parent-directed
handoff is to the existing editor-fixture/readiness planning task. Publication, CI reruns and
source-planning activation remain outside this packet.

## Local validation

- PASS: 12 source/inverse/scope/cost regression tests, including negative mutations.
- PASS: exact two-file inverse and unchanged protected original source/profile/guard/workflow.
- Apple Swift compilation/XCTest, UI AX/menu/dismissal runtime verification: NOT RUN.
- Current combined complete-shard planning and aggregate tests: owned by unified integration;
  not claimed here.

Required Apple validation must reach every original assertion after both barriers. Any barrier
timeout remains a real failure with the app hierarchy attached and requires diagnosis.


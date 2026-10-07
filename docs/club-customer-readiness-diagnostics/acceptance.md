# Customer-choice entry readiness diagnostics

Independent baseline: commit `7dd74b54a9aff8260198e5c00bc2feaac68337fe`, exact tree `4145c2a180e313844efbc5491e81893ccbe60b93`. This is a pure test/diagnostics patch. Existing activity, cooperation and Club admin packets remain frozen and are not dependencies.

## Observed failure and visual evidence

Run 129, job 112729141657 failed ModuleFlowTests.testClubCustomerChoiceDeniedAndWrongMemberFailClosed at original line156. It was the first tuple, customerDenied/member704. The existing helper's configured ten-second `exists && hittable` expectation timed out before any tap, choice menu or private customer read. The wrong-member tuple was never reached in this failed execution.

The late AX tree contains a single member704 button at frame(20,499.3,380,70) within a 420×912 application. The actual 10:39 failure screenshot, 036ACDF8-CF92-4ED0-A411-0C9AFDBDFEB8.png, shows the complete Members list with member704 and no menu, customer destination, alert or visual obstruction. These are post-timeout observations. Neither the frame nor screenshot establishes that the element existed or was hittable during the earlier predicate evaluations.

The same helper later succeeded for customerOwner/customerAdministrator. At the exact source baseline, customerDenied sets only the subsequent governance-read failure; the list member button is constructed through the same branch. There is no evidence to relax privacy checks, assume a production authorization defect or declare infrastructure as the cause. Source/readiness and precise runtime timing remain separate questions.

Artifact 11477840079 was downloaded read-only. Its 2,819,698-byte ZIP SHA256 exactly matches the job's published digest. The failure image and bounded failure-log excerpt accompany this candidate; source metadata is recorded in run129-evidence.json.

## Bounded test-only observation

Only this one method calls a dedicated readiness helper. It uses the same passed XCUIElement, the same `exists && isHittable` condition, configured ten-second waiter, unchanged completed-result assertion and one tap only on completion. The original shared helper and all other methods are byte-identical.

Each predicate evaluation reuses its required exists/hittable reads and records their beginning/end uptime offsets and boolean results. At most 16 evaluations are retained. On failure, the immutable waiter result remains failed while the helper records explicitly labeled AFTER_TIMEOUT_ONLY existence, hittability, enabled state, frame, sheet/alert count and app state. Those late values cannot turn the failed result into success. No coordinate tap, fallback query, extra tap, scroll, retry, sleep or additional wait is added.

The case's original customerDenied/member704 and customerOwner/member703 tuples, customer-choice target, rejection assertion and both private-data absence assertions remain intact. No App/Core/fixture/read/write permission, navigation or backend change is included. Diagnostics are confined to this synthetic fixture test. Additional diagnostic work can affect failed-test execution time and therefore cannot establish a production repair by itself.

Three source checks include negative controls against dropping hittability, enlarging the timeout, adding a tap, bypassing completion, removing either private-data absence assertion, or substituting the wrong-member case with the allowed member. They protect the failure boundary; they are not Apple results.

## Remaining execution

The original failure stays OPEN. Swift/Apple SDK compilation, targeted XCUITest rerun, new predicate samples, new screenshots and device interaction are **NOT_RUN** here. Root/reviewer owns integration and targeted rerun scheduling; no workflow was dispatched by this lane. No new UI method or shared duration-budget entry is introduced, and no failed prefix is treated as a complete-method timing sample.

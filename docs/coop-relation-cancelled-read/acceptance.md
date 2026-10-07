# Cooperation discovery cancellation cleanup and hosted diagnostics

This independent patch starts at published commit `7dd74b54a9aff8260198e5c00bc2feaac68337fe`, exact tree `4145c2a180e313844efbc5491e81893ccbe60b93`. It does not depend on the activity/image packets and does not change any of those nine frozen artifacts.

## Two separate findings

Run 129, job 112729139694, recorded `CoopRelationPresentationOwnerTests.testHostedCoveredListPopsVisibleProfileAfterAccountReplacement` failing at its original line 87 after 2.437 seconds. The failed predicate combines four states: no selected presentation, child not visible, parent no longer covered, and current discovery model. The log contains none of their individual values. Four other methods in the owner suite passed. The reported CancellationError immediately following the assertion is thrown by the test's own wait helper after XCTFail; it is not independent evidence of a business-service cancellation error.

Consequently this patch does **not** claim that the account-replacement pop failure is diagnosed or fixed. The single hosted method now emits synthetic booleans and request counts only when that same wait fails. Its predicate, every assertion, the 100 × 20 ms maximum wait and the thrown failure are preserved. No identity, token, profile content, URL or real account data is logged. Root/reviewer owns the next targeted Apple run; this lane did not dispatch it.

Separately, the exact Core source proves a loading-state cleanup gap: load first invalidates and sets isLoading=true, then its success and error paths can both return early for cancellation, changed owner/session or stale generation, bypassing the only loading=false assignments. An already-canceled invocation also formerly invalidated the shared model before discovering cancellation. These are control-flow findings independent of which conjunct failed in the hosted test.

## Minimal correction

Core/CoopRelationDiscovery.swift now rejects an already-canceled Task before invalidate(). Once an invocation owns a generation and starts loading, a defer clears isLoading only while that exact generation remains current. A stale completion cannot finish a newer load. All original session/reader/current-predicate/generation/Task publication fences, existing success/failure assignments, authorization handling and selection semantics remain intact.

The presentation owner, discovery View, fixture, merchant/club adapters, Session/Composition, storage, localization, Workshop, runtime permissions and network requests are unchanged. Project regeneration is byte-identical: the existing Core test target discovers the added test file automatically. Shared UI tests, inventory, duration weights and CI are unchanged.

## Regression scope and execution limits

Four new Core XCTest methods author deterministic held-reader scenarios for current cancellation, owner predicate/session replacement, canceled old completion while a newer request is still loading, and an already-canceled invocation after a newer snapshot has been accepted. The synthetic reader deliberately ignores cancellation so the existing publication fences and generation-specific cleanup must handle the late reply. Dispatch expectations synchronize a specific event; they do not lengthen the existing hosted timeout or hide a failure with sleeps.

Three supplementary Python checks preserve the original hosted assertion/wait and the existing Core safety conditions. Local source tests, project/scaffold and advisory parser output are attached separately.

Swift typechecking, Core XCTest execution, hosted AppUnit rerun, simulator/device navigation and the new diagnostic observation are **NOT_RUN** in this Linux executor. Source/static passes do not equal Apple execution. Run129's hosted failure remains open until the unchanged predicate passes with evidence on a reviewed integration. No publish, push, workflow dispatch or production call was made.

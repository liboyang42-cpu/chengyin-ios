# Poster confirmation preflight follow-on

The first media packet allowed the same confirmation review to remain eligible while its asynchronous current-node read was suspended. A second confirmation could complete and clear the durable lock before the first resumed, allowing another dispatch against a frozen host snapshot.

The coordinator now consumes the review and enters `preflighting` synchronously before any suspension or change callback. Each confirmation gets a fresh generation, and repeated confirms outside `review` are no-ops. Attempt, phase, cancellation, session, current-node eligibility and location freshness are checked again before the durable record. Cancellation after that write keeps the unknown-result lock and is rechecked before dispatch. A failed or canceled preflight cannot replay its consumed review.

Three new controlled-continuation tests cover:

1. A held first-confirm refresh and concurrent second confirm; only one dispatch, even when the accidental second read would return immediately and its successful response would clear the journal first
2. Coordinator cancellation while preflight is held; zero journal writes and zero dispatches
3. Task cancellation while preflight is held; zero journal writes and zero dispatches

The preflight status has its own bilingual string. Default hardware, endpoint and media grants are unchanged and remain off.

A pre-existing publishing structural assertion previously sliced from the publishing factory through unrelated later AppSession factories. Its extraction now stops at that factory's own closing indentation. It still asserts that the publishing factory has no journal injection.

Local evidence: strict parser pass for the three changed Swift files; media/source guards, scaffold and existing retained-image checks pass; 435 Python contract checks run, 37 external-source comparisons explicitly skipped. Swift/XCTest/Apple simulator runtime remains **NOT_RUN locally**. These authored regression tests require the Apple CI owner's execution before claiming runtime proof.

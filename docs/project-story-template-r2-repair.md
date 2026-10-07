# Story-template R2: confirmed existing-envelope save and strict inner JSON

## Review findings addressed

The frozen first candidate remains separate. Its shared local save wrote a new envelope and then the active pointer. If only the second write failed, the editor reported failed adoption while the insertion was already durable. Cancelling and cold reopening without an intervening editor leave could recover that unconfirmed insertion.

R1 tried reordering the shared save with pointer rollback. That experiment was **not adopted** because cross-identity pointer rollback failure could reduce discoverability of an older draft. Its source and logs are retained separately as rejected review evidence. No R1 shared-save or dependent-test changes belong in R2.

R2 leaves the shared save and all its existing callers unchanged. The chooser instead uses a narrow existing-draft replacement:

1. The local draft must already have a valid saved envelope with the same account, namespace, identity, personal city product/owner and base revision. A new-draft active pointer must already identify that exact draft.
2. Bounded, duplicate-key-safe preflight occurs before typed pointer/envelope decoding. The complete persisted envelope must survive lossless typed roundtrip, and its draft must exactly match the current expected preimage, including Unicode bytes and pending-material metadata. Unknown durable fields are rejected rather than dropped.
3. The replacement writes exactly one envelope item. It neither writes a pointer nor falls back to the ordinary save. The secure provider's existing atomic single-item replacement is the commit boundary; this is not a claim of cross-key transactions.
4. The editor updates only after success. A missing, dirty, unreadable, conflicting, or foreign preimage refuses with zero writes. An unsaved chooser opening issues zero list calls and displays “Save this draft on this device first, then reopen.” A failed single write keeps the old saved envelope and can be retried explicitly once.

The second finding was duplicate fields hidden inside the advancedConfigJson string. The outer HTTP JSON parser cannot inspect keys inside that string. R2 bounds the inner document to 262,144 bytes and runs the existing bounded grammar/duplicate-key parser before either typed decoder. Duplicate album/enabled/timer/image keys and escaped aliases are rejected. A single valid escaped spelling remains accepted. Existing depth/token/string/atom preflight limits also apply.

## Tests and evidence

Added real Swift test bodies, not substitutes implemented in Python:
- 9 release-independent Core narrow-save methods: existing/new/topic identity, missing/foreign/conflicting/corrupt pointers and envelopes, exact preimage, Unicode/unknown-field preservation, read errors, one-write success/failure/retry, second-write nonexistence, and cold storage readback.
- 3 Core inner-JSON methods: duplicate and escaped-alias keys, valid escaped control, and bounded size/depth/string/atom/grammar cases.
- 4 App methods: ordinary/album exactly-one-write adoption, single-write failure then Cancel/cold restore without old editor.leave(), single retry and no duplicate insertion, unsaved/dirty/unreadable opening without list reads, and a conflicting pointer after review with no fallback.

The prior 17 Core selection and 20 App selection methods remain byte-identical. All pre-feature Tests files, all six UI journeys and their shared helper, the shared ordinary save body, live duration profile and CI workflow remain unchanged. The previously authored 33 Core methods therefore become 45; App methods become 24; UI methods remain six. Swift/Xcode execution is still NOT_RUN. Supplementary parser and Python source checks do not establish Apple execution.

R2 does not alter the six whole-method UI budget identities or estimates. Budget/history integration remains owned by the separate integration candidate. The local-only submission limitations, default-nil production reader, special chapter rules, and backend LOCATION_FREE_UNSUPPORTED boundary remain unchanged.

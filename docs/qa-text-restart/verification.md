# Ordinary text QA restart recovery: source and shared handoff

Immediate base: public `codex/qa-receipt-recovery-20261108`,
`68626f0c31162a0108df9eaf3d658c9f09cb83fd`. Public main remains
`3971086a1feb3dc765a44153542c1d52eb9e4775`. This incremental branch is
`codex/qa-restart-receipt-20261108`; it does not replace or re-upload the earlier
word-fill/QA candidates. Reaction, points ledger and backend owners are excluded.

**This is not active App restart recovery yet.** Shared Runtime, AppSession,
Composition, PBX and existing hosts remain byte-identical to the base. The typed
encrypted adapter and host changes are exact handoff patches for the integration
owner. Apple compilation and App acceptance remain required.

## What was verified before implementation

- `PlayDurableRecovery.swift` owns a private AES-GCM `PlayEncryptedSlot`, with
  immutable ciphertext generations, permanent presence marker, Keychain CAS,
  bounded reads, authenticated scope and committed clear tombstones. Its SHA-256
  is `39f742f576a426608552983eac349857f516f10c29239a92f164b9be406a2149`.
- Existing normal Play `PlayCompletionIntent` is a different action and contains
  completion evidence. A text QA receipt identity must not be disguised as that
  intent. The private engine can be reused by adding a typed adapter in the same
  shared file; its existing implementation remains unchanged.
- Existing `ContentDraftSystemStorage.swift` supplies the reviewed OS primitives;
  SHA-256 `cb88a0205098acea4384887585c206416969d3ff23ca5bbadb348031d122059d`.
  No new cryptography or alternate storage primitives are added to production.
- `TemplateAuthoringSecureStorage` uses device-only unlocked Keychain, but its
  blind upsert interface lacks the existing journal's CAS/presence loss detection.
  It is deliberately not used as an automatic fallback.
- The current advanced host has no durable QA injection. Its generic runtime
  session selector also omits role, defaulting to `player`; the proposed advanced
  host selector binds the actual recognized account role without changing other
  selectors. A retired read lifetime must restore redacted metadata into a fresh
  approved reader, not inherit an old answer payload or action grant.
- Backend HEAD was rechecked as
  [`147754ba8740abf208bda75cf86ed5901cac4c02`](https://github.com/liboyang42-cpu/hengyin/tree/147754ba8740abf208bda75cf86ed5901cac4c02).
  Its existing [receipt reader](https://github.com/liboyang42-cpu/hengyin/blob/147754ba8740abf208bda75cf86ed5901cac4c02/chengyinhub-system/src/main/java/com/chengyinhub/business/service/support/AdvancedActionReceiptReader.java)
  accepts the original `sessionId` and `idempotencyKey` and returns the owned log
  view. 404 remains absence of proof. No new endpoint, verdict or backend field
  was inferred. Existing contract source hashes remain in the prior delivery.

## Implemented owned source

`PlayQATextReceiptRequest` separates original session/version/key and expected
activity/topic/node from `PlayAdvancedPending`. It has no answer, token, payload
or action POST representation. Both the live pending adapter and the restart
reader use the same exact receipt decoder and original GET route.

`PlayQATextRestartRecord` stores only that redacted identity, the exact existing
recovery owner, deployment and route/node context, and a local file schema. These
are local persistence fields, not additions to server JSON. Auth epochs are not
part of the durable slot, so reauthentication after relaunch can read the same
owner's record. Credentials and answer text never enter the record.

The slot binds deployment + existing `PlayRunStorageKey` + node. Role and expected
activity/topic are validated inside the encrypted record, so a role/configuration
change encounters the old unresolved lock rather than creating a fresh empty
slot around it. Another account/namespace/route has a separate binding.

`PlayQATextRestartRecovery` implements local load, durable reserve and explicit
receipt reconciliation. It exposes no action/start method. Loading a record does
not contact the backend. A reservation always means unresolved, including a crash
before dispatch; even the same key cannot reserve over an old record.

Reconciliation uses only the original receipt identity. It checks the current
owner/epoch/token before accepting the returned view and after durable clear.
404/409, wrong identity, malformed response, disabled reads and lost transport
retain UNKNOWN; storage failure blocks new actions. 401/account withdrawal hides
the result and retains the record. A changed epoch cannot expose an earlier view
or reuse an empty-slot authorization from an older load.

There is one internal acknowledgment bridge for the coordinator's directly
awaited original POST response. Its only proposed call site follows the existing
`advancedAction` response binding and owner/generation validation. It clears the
exact reservation before accepting that response. Generic state/version reads
and restart recovery cannot use this bridge. It acknowledges the request, without
interpreting whether the answer passed. After a matched server failure is recorded
and the lock clears, the next separately reviewed answer can reserve a new key.

## Exact shared activation handoff

Apply the owned-source commit and both patches as one reviewed integration set:

```sh
git apply --check docs/qa-text-receipt/integration.patch
git apply docs/qa-text-receipt/integration.patch
git apply --check docs/qa-text-restart/integration-after-receipt.patch
git apply docs/qa-text-restart/integration-after-receipt.patch
```

If the first receipt patch is already integrated, apply only the second against
its exact documented preimages. `integration-preimages.json` pins every resulting
file. Do not blindly overwrite integrated shared files when their hashes differ.
The previous delivery's source manifest is historical to commit `68626f0...`;
this directory's `source-manifest.json` pins the incremental owned source.

The second patch adds the typed journal in `PlayDurableRecovery.swift`, a fixed-root
OS factory, precise Runtime/AppSession/host hooks, four source registrations and
two Core test files. It proposes:

1. Load the QA-only node journal locally before offering any replacement advanced
   start. An existing identity blocks start; no new session is treated as receipt.
2. Reserve the original frozen TYPE review identity durably before the first POST.
   Storage failure prevents that dispatch. HANGMAN/PICK/SHOT and other action
   payloads are never stored as text QA.
3. For a valid original awaited POST response, clear the exact durable generation
   and accept only its server state. On UNKNOWN, keep the original lock.
4. After relaunch, keep restored metadata separate from `PlayAdvancedPending`.
   Do not fabricate an empty input payload. Explicit recovery GET reads the old
   session/key, validates the existing state parser and original context, then
   clears the matched generation. It never calls action/start.
5. A fresh approved read lifetime can construct a new redacted recovery reader.
   It does not carry an old answer or grant. Other owners' no-rebinding locks,
   including an unknown start with no original session ID, retain their behavior.

Fixed OS roots are a separate `PlayQATextReceipt-v1` Application Support directory
and `questify.play.qa-text.receipt.v1` Keychain service. No production capability,
transport, endpoint default, CI policy or AppSession-wide storage fallback is
enabled. The old constructor's nil journal remains compatible with existing
synthetic callers; that memory-only mode must not be called restart recovery.

## Tests actually run

Cloud Linux, Swift 6.0.3: **33 XCTest cases passed**, zero failures:

- 11 existing original receipt query/identity/failure-policy cases.
- 16 real restart component cases: redacted round-trip, owner/realm/role/scope,
  schema rejection, empty-slot lease fencing, pre-dispatch reservation, restart
  with original key/session, no automatic reads, 404/409/malformed retention,
  account/epoch ABA and 401, wrong receipt, clear failure, a subsequent distinct
  answer after server failure, and original-response acknowledgment binding.
- 6 typed encrypted-adapter cases: exact reopen, encryption, duplicate reservation,
  stale generation, role/topic lock, lost anchors/presence/corrupt ciphertext,
  interrupted reserve and interrupted clear tombstone recovery.

The runner compiles the actual new source, exact existing production declaration
slices, the unchanged private encrypted engine and the exact adapter fragment
included in the shared patch. Synthetic actor stores are extracted from the
existing test fixtures. No cryptography is stubbed. Linux uses official
`apple/swift-crypto` 3.9.1, commit
`06dc63c6d8da54ee11ceb268cde1fa68161afc96`, re-exported under the CryptoKit module
name only in the disposable package. This does **not** execute Apple's CryptoKit
implementation or OS storage. Transitive dependency revisions are recorded in
`portable-test-evidence.json`; no package dependency was added to the App.

```sh
python3 tools/test_qa_text_restart_candidate.py --swift /path/to/swift \
  --swift-crypto /path/to/pinned/swift-crypto-3.9.1 --output /tmp/qa-restart-tests
python3 tools/verify_qa_text_restart_handoff.py --swiftc /path/to/swiftc \
  --output /tmp/qa-restart-handoff
```

Both patches applied in a disposable source copy. All exact pre/post hashes,
unchanged encrypted-engine declarations and registration-only PBX changes passed.
Scaffold passed with 2,168 App/Core/AppUnit/UI source files and 10,340 bilingual
keys. Swift frontend parsing passed for proposed shared files, factory and tests.
The actual checkout's shared files remained unchanged. See `handoff-evidence.json`.

## Unverified and still blocked

- Two full real-Runtime Core test cases are supplied in the shared patch for cold
  restore/404/no replacement start and input-review-UNKNOWN-restart-original GET-
  server failure-next review. They are syntax parsed but **not executed**. The
  33-case run does not exercise the full production Runtime or HTTP service.
- No Apple type compilation, Security/filesystem storage acceptance, full Core
  regression, AppUnit, simulator/device, App acceptance or live backend call ran.
- Shared activation is pending root. Until that set is compiled and exercised,
  the App still has memory-only advanced recovery. This source delivery is not an
  App restart acceptance claim.
- A lost original advanced START response has no known original session ID/key
  to query. It stays blocked; this change does not create a substitute session.
- Existing numeric-only advanced ID parsing still rejects string-projected large
  IDs. Those results remain UNKNOWN rather than broadening the shared wire parser.
- Unknown storage schema, lost secure anchors and an interrupted reservation with
  no readable ciphertext remain unavailable. No reset/expiry/automatic discard
  policy is invented. A pre-dispatch crash can therefore leave a receipt 404
  barrier; 404 is never relabeled as proof of nonexecution.
- Source-inventory CI ledgers remain unchanged. No CI pass is claimed; no workflow
  was started, retried or adjusted. No PR, production write or main change occurred.

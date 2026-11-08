# Blank-fill client format and integration boundary

This is a dormant native input component. It is not registered as an enabled
game, does not decode a backend response, and cannot submit a request by itself.
`PlayWordFillView()` is unavailable by default. This source group is ready for
review; backend integration and App acceptance remain open.

## Confirmed client behavior

`PlayWordFillQuestion(format:)` treats each ASCII `_` as one blank. Every other
character is prefilled and preserved, including spaces, punctuation and connector
words. It does not infer a mask from a correct answer or normalize the format.
An explicit `.prefilled("_")` slot remains available for a literal underscore;
the backend's escaping/representation, if needed, is not defined here.

The keyboard accepts only the missing characters in order. Prefilled characters
never consume keyboard input. Examples exercised by the tests:

| Public format | Player's missing-character input | Reconstructed text |
| --- | --- | --- |
| `E_____S` | `NDLES` | `ENDLESS` |
| `_______ AND ________` | `NICOLASPERNELLE` | `NICOLAS AND PERNELLE` |

The source-document prose supplied to this implementation also shows `E____ S`
beside the first input/output pair. Under the stated one-underscore/one-blank
rule that literal format has four blanks and a fixed space. Five input
characters cannot fit it. The tests therefore reject this combination; the
client does not delete the space, add a blank, or consult an expected answer.
The content/backend owner must resolve the actual public format before enabling
that question. The five-blank test above validates the given input/output vector,
not an assertion that the prose mask is a complete backend JSON example.

The supplied evidence is the construction document's lines 2760–2761 and
2889–2892, document SHA-256
`542b87062acfdbd1614c17c24a5606775edc2f8c4eec782f3d3fa1ef5cdac2e4`.
Those excerpts were provided by the integrating owner; this work did not
independently obtain and hash the entire document. They distinguish blank-fill
keyboard/letter-set input from image choice. No traditional letter-guessing,
automatic matching-letter reveal, local answer table or penalty mechanic is
implemented.

## Draft and review behavior

`replaceBlankInput` preserves partial, IME and overlong input; extra characters
are not silently discarded. Review input exists only when every blank has one
non-whitespace, non-C0/C1-control grapheme. Rebuilding preserves the entered and
prefilled UTF-8 bytes, case and width. A complete input is not a correctness or
completion result.

`PlayWordFillContext` binds the exact public question to a host-issued revision.
The host must rotate it for owner, read lifetime, session, node, authoritative
version and question changes, including ABA changes. A separate mount ID retires
old keyboard bindings on remount. Leaving or suspending the view clears the
unsent transient draft. No answer text or command is persisted by this component.

The only output is `PlayWordFillSubmission`, an immutable reconstructed input and
its context. It is a candidate for the existing frozen-review flow, not a new
wire contract, action ID or result. The host must validate its context again.

## Deliberately unresolved integration

- The backend owner must provide the exact public projection, route, action,
  payload, question identity, state version and terminal/result semantics.
  This component reads no speculative `playKit` key or author configuration.
- The documented `validAnswer.text` denotes the full reconstructed text. The
  actual native adapter and the source of `options` / `createdAt` are not
  invented here.
- Hint, opportunity, skip and reveal actions must retain their existing server
  rules and receipts. Neither those actions nor a letter-set restriction is
  synthesized by the input component.
- The integrating runtime must retain and reconcile the original pending action
  and identity across response loss and restart. A changed server version or a
  filled input is not proof the original action succeeded. The existing advanced
  coordinator's in-memory pending property alone is insufficient restart evidence.
- Shared AppSession, Composition, Runtime, PBX and action catalogs are unchanged.
  Once the backend contract is confirmed, the integrating owner can register the
  source/catalog using the existing project generator and connect the original
  review/recovery flow. No normal entry point is enabled by this commit.

## Verification

The 24 `PlayWordFillDraftTests` passed under Swift 6.0.3 on Linux in an isolated
package containing copies of the real model and test source. They cover both
documented input/output pairs, strict format parsing and the ambiguous prose
mask, prefilled immutability, independent repeated letters, graphemes and exact
bytes, invalid/partial/overlong input, frozen snapshots and stale callbacks.

Reproduce without altering the project's shared registration:

```sh
python3 tools/test_word_fill_client.py --output /tmp/word-fill-client-evidence
```

The script records the tested source hashes and XCTest log. It does not run a
backend, full Core regression, SwiftUI type check or App acceptance. Swift syntax
parsing and catalog JSON validation also passed. Apple SDK/Xcode compilation,
simulator/device rendering, real keyboard/VoiceOver behavior, server action
dispatch, account changes and original-action restart recovery have not run.

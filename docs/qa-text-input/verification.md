# Ordinary text QA input and verification

This change applies only to the existing PlayKit `qa` / `TYPE` input. It adds no
gameplay type, answer table, judgment, request field or backend action.

The previous TYPE form used the shared `textBinding()`, which immediately called
`PlayKitInputContract.limitText(..., toUTF16: 4096)`. An overlong paste therefore
became a shorter prefix before the player opened the frozen review. The new
form preserves the complete text, displays a length error and rejects review
until the player explicitly shortens it. Existing valid input is neither
trimmed nor normalized. The 4096 UTF-16 bound is the existing input contract.

The real `qaForm` TYPE branch now mounts `PlayQATextAnswerForm`; SHOT and PICK
remain unchanged. The form uses the current coordinator/read lifetime, session,
node and version, rejects retired text bindings, and calls the existing
`prepare("SUBMIT_QA", ["input": ...])` review outlet. It does not generate an
action ID, HTTP request or result. Original review/owner checks, pending request
identity, server verdict and recovery remain in the existing runtime.

App/Core source and the independent `PlayQATextInput.xcstrings` catalog are
registered in the actual app PBX. Registration adds only the new file/build
objects and references; existing targets, settings, build phases and entries
are preserved. The full generator's unrelated object reordering is excluded.
Core tests remain discovered by the existing Package.swift test path.

## Observed checks

- Swift 6.0.3 Linux compiled, linked and ran the isolated production input model:
  10 regression tests and 2 reproductions using the unchanged production
  `limitText` method passed. The reproductions demonstrate lost suffix/emoji in
  the old function and retention plus blocked review in the new input model.
- `tools/check_scaffold.py` passed its references, bilingual keys, schemes and
  semantic project equivalence checks. This is a structural check, not Xcode.
- New Swift syntax parsing passed. The app form's SwiftUI types have not been
  compiled with an Apple SDK in this Linux environment.
- No CI workflow, trigger, test selection policy or inventory ledger is changed.
  The current source ledger requires regeneration after source changes; its
  check is not claimed to pass. CI is not manually started, rerun or adjusted
  as part of this change.

Reproduce the isolated Swift test scope:

```sh
python3 tools/test_qa_text_input_candidate.py --output /tmp/qa-text-evidence
```

The script copies the actual model/test files and extracts the actual unchanged
production truncation function. It records their hashes and the XCTest log; it
does not substitute a network stub for App or backend acceptance.

## Remaining validation

Apple app/type compilation, simulator/device rendering, real IME/VoiceOver,
confirmation/cancellation and account-switch UI flows, live server verdicts,
original-action response-loss/restart recovery and full repository regressions
remain unverified. In particular, advanced QA's in-memory pending property is
not proof of process-restart recovery; the separate classic answer durable
journal must not be conflated with it. No runtime change or production enablement
is included here.

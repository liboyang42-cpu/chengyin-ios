# Participant phone validation: current mini parity

This is a bounded correction to existing participant create/edit, not a new complete contact-person feature or production activation.

Source: private `chengyin` commit `0bf8a3b13e601a82ed8b4902d775a6ed290bc26b`.

- `chengyinhub-xcx/pages/addressinfo/addressinfo.wxml` binds visible name/mobile inputs and save controls to `onInputChange` / `saveAddress`.
- `pages/addressinfo/addressinfo.js` uses `utils/form-state.js` `isValidMobile` in form validation and submission readiness.
- `utils/form-state.js` defines `^1[3-9]\d{9}$`.
- `chengyinhub-admin/.../api/ApiUmsMemberController.java` `userAddressActoin` trims input and rejects mobile values not matching the same pattern before writing an owned address.

Native `ParticipantFormDraft.validation` formerly admitted 10/11/12 prefixes under an older Flutter contract. It now requires 11 ASCII digits, first digit 1, second digit 3–9. Surrounding whitespace is trimmed as before; internal spaces, country prefixes, masks, full-width digits and reconstructed numbers are not accepted. No carrier allocation lookup is inferred. Existing draft fields, hidden metadata preservation, confirmation/session fences, request IDs, and unknown-write readback locks are unchanged. Invalid create/edit drafts fail both confirmation preparation and transport preflight. The activity checkout has a separate contract and is deliberately unchanged.

The participant-specific bilingual hint and its localization source are updated. No default button is added: current mini address WXML does not bind its retained `setDefault` handler and comments out the default badge. The existing default capability remains dormant in UI. Existing ProfileReadScreen appearance tasks already refresh list reads on navigation return; no speculative navigation change is included.

Tests add form boundary vectors for all allowed second digits and rejected 10/11/12 prefixes, plus create/edit service and coordinator no-dispatch assertions. Existing repeated-confirmation, session replacement and unknown-outcome tests remain intact. Python contracts/scaffold/tooling and supplementary syntax checks can run on Linux; Swift compilation/XCTest and Apple UI/device acceptance require the Apple toolchain and are not claimed by these checks.

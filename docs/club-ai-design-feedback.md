# P045 AI idea chips and promotional-copy feedback

Base: `ea9d4c429237aeecfb1bbc4b4f6d0713c4fa59dd`. This packet is independent of sealed Club21.

## Source and entry

The sole master document's P045 lines1652–1655 indexes `onClubAiChip` and `onClubAiCopy`. Mini-program revision `f859cd6e2618f618a53f5cd33949259828e86313`, `detail.js` blob `b49b5fb14caf49d47e971cd93ffd73cd94d8e044`, defines three ideas on line39, replaces only `aiIdea` on line1357 and copies the exact nonempty `aiPromoCopy` on lines1418–1422. `detail.wxml` blob `033ac08d82e76b8b92853b7eda9b4c65a7ce7804` exposes chips and copy at929–931/989–992.

Ordinary entry: club detail → existing owner AI-design entry. Three source-authentic idea buttons live beneath the original inputs. Selection replaces only the idea and leaves style, duration, freeform editing, generation and adoption intact. Existing owner/identity/network permissions are unchanged. The result's original selectable promo text remains present; a nearby explicit copy button writes that exact text to the local-only clipboard.

## State and privacy

Each interaction lease binds the club, full publishing identity (namespace/account/epoch/role/region), original view operation UUID, result generation and exact UTF-8 promo bytes. The live flow result accessor independently checks its current identity provider before a clipboard write. Generation's synchronous busy flag closes the window before the async task starts; flow busy closes the in-flight window. New generation or cancellation changes the original operation UUID and retires earlier feedback. A failed new generation retains the prior candidate under the existing design but requires a new explicit copy action and can never keep a stale success message. Replacement results cannot be copied by old rendered callbacks.

Disappear, scene inactivity and re-entry retire interaction leases; context ABA cannot revive old callbacks. Clipboard writing is synchronous. The model checks scope immediately before writing and again before accepting success. Success is displayed only after the platform writer observes a new pasteboard change count and string contents availability; failure exposes a manual retry through the same button. Unsupported clipboard platforms return failure. No network, clipboard readback, share sheet, uploader, universal-clipboard transfer, automatic copy, generation request or adoption occurs in these helpers.

Idea selection is a local form edit gated by the current rendered publishing scope and view lifetime. It does not claim backend identity verification; original generation authorization remains authoritative. Promo copying additionally verifies the live result owner through the existing flow.

## Review and verification

Only two added call lines change `ClubAIDesignView.swift`. Removing them yields its byte-exact baseline. Original generation, cancellation, error, result-retention and adoption code and all of `Core/ClubAIDesignFlow.swift` are untouched.

The packet includes13 core tests and12 app-model/flow tests covering exact chips/text, busy handling, writer success/failure/retry, stale operation, identity loss, result replacement, failed regeneration, cancel, visibility, context ABA and stale completion. The app-model tests call the actual existing flow and the production adapter; they do not substitute a Python/JS implementation of the Swift state machine. They are authored but NOT_RUN here because Swift and Apple tooling are absent. Exact mini-program handlers run in Node without requests. Targeted Python source checks and Tree-sitter parsing supplement, but do not replace Swift typechecking or Apple UI/runtime tests.

No PBX/catalog/CI change is included. Registration and bilingual localization fragments are supplied for root integration. P043/customer-note-editor remain canceled; old failures are not repaired. No actual backend or clipboard operation was performed during this cloud implementation.

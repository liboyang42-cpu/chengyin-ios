# Simple-create inspiration selection

P035 `useAiPrompt` has three source-backed suggestions before a plan exists. The ordinary AI draft sheet now offers those three bilingual actions before the existing editable idea field. Selection replaces only the local idea, clears its prior error, and focuses the existing input. The user may continue typing and then explicitly use the existing Generate action.

Suggestion selection cannot call a provider or change quota, approvals, candidates, confirmed POIs, saved drafts or publication state. It remains local when no provider exists. An attached account must match the sheet's opening owner; old callbacks also fail after input changes, generation, a candidate, closure, or stable-page retirement. Existing candidates keep their original controls and provenance. Generated title/node edits and place confirmation already belong to the Quick editor and are not duplicated here.

The controller belongs to the stable AI sheet; lifecycle attaches to the whole Form. Lazy suggestion rows have no presentation or lifecycle owner. Source-supported Chinese ideas are preserved; English labels and inserted ideas are equivalent translations.

Source: Mini commit 95e499471eaa39c28f77d16125f0cc17b8c37123, simple/index.js blob b4cd5b8d7b95ec28e6a123354a53d4e1f28bc1c6 and index.wxml blob 17f6d9de1065c51d49b30a2515388486d5e97264. Private source modules are not distributed in this increment.

Validation: focused source/grammar/registration checks and a pinned Mini handler fixture. Three Core and two App test methods are authored. Real Swift compilation and Core/App/UI execution are NOT_RUN in this environment.

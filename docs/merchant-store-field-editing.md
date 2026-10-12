# P079: complete store text-field editing group

Actual Mini `pages/merchant/decor/index.js` defines six fields: name, preference, description, derivativeBenefits, slogan and cityRole. Its open/input/confirm/close/keep/discard actions stage each field independently. This feature covers that complete group, including description on the existing story destination. It does not duplicate P081 cooperation settings, tags, category selection, images or template editing.

Each existing profile/decor/story entry opens a field buffer. Apply changes exactly one property through the original `MerchantOperationsViewModel.edit` method. Dirty Cancel asks to discard only that field; Keep editing retains exact raw input. Other draft changes, optional missing benefits, hidden decoration/cooperation values and business-time replacement survive unchanged. Legacy derivatives and website fields retain their original direct controls.

Source limits are 100 UTF-16 units, or 300 for the brand story. Changed store names must not be blank. Values are neither truncated nor normalized; unchanged historical values are a no-op. The source immediately saves a confirmed field, while native scope remains local preparation followed by its existing whole-draft review and unchanged write gate. No request, permission, upload or production save is added.

Owner revision, account scope, draft identity, original baseline and all raw text siblings guard the buffer. Reload, source/draft changes, review, account change, background and departure retire it. Route generations and identity-bound presentation bindings prevent old callbacks from affecting reopened fields.

Integration is nine new leaves and four exact edits in `MerchantOperationsEditor.swift`. No shared host is overwritten or applied. The sealed P081 helper proposal remains independently applicable. Central target registration and sixteen bilingual keys are listed in evidence.

Verification is limited to source checks, actual Mini local-handler/confirm-routing oracle with saver stubs, Swift grammar and patch byte proofs. No actual saver or network executes. Native compilation, 17 Core +22 AppUnit +5 UI tests, VoiceOver, large text and simulator/device behavior are NOT_RUN without Apple tools. UI tests reuse the existing operations offline fixture and never confirm a business save.

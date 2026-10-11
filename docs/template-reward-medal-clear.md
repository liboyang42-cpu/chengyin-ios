# P036: Clear medal

The native template reward form now has **Clear medal / 清除勋章** beside its medal fields. One explicit tap clears the medal image reference and name and resets the style to glow. The reward module stays enabled; coupon, feedback text and all unrelated fields remain unchanged.

This follows the master P036 clearMedal event and the Mini implementation in temp-index.js lines 1802–1804. The source WXML exposes its clear control within the medal configuration. The native form previously offered only separate image, name and style fields.

## Contract and lifecycle

The implementation uses the existing medalImg, medalName and medalStyle fields. Image/name clear to nil, consistent with the native optional text bindings; the existing serializer omits their empty values and omits style when neither medal field remains. No server-side deletion is implied. The existing reward validation still requires coupon, feedback or a complete medal before publication.

No data changes on opening or preparing the action. Partial, whitespace, opaque-reference and unknown-style historical medals can be explicitly cleared. The default already-empty glow state is a no-op. A captured action checks exact UTF-8 bytes of all three fields as well as model/media generations, session, draft identity and edit availability. Repeated actions and callbacks after target edits, reload, restore, discard, review preparation, dismissal, owner change or durable write lock do not mutate the draft.

The action writes the current draft atomically through the existing local authoring coordinator. It needs no service factory, upload, URL access, permission change or new persistence field. It preserves all prior choice-row, audio and story-image editing changes.

## Verification and integration

Six authored Core tests cover exact three-field mutation, default/disabled state, partial and historical data, stale byte identity, payload and validation. Seven authored App tests cover fresh local save/restore, repeated action, direct and ABA changes, lifecycle and owner changes, and durable pending locks.

Six focused Python contracts inspect the actual UI route, guards, limited mutation, unchanged earlier feature entries and additive fragments. These do not execute Swift or native UI. The authorized current computer lacks Swift/Xcode, so Core/App tests and Apple UI/accessibility acceptance remain NOT_RUN.

The candidate starts from 51d3e24de92427a777f8690f847cec39971b041a with the sealed choice-row dependency applied. Integrate the provided registration/localization fragments through the normal central workflow. This worker changes no central PBX/catalog/CI files and performs no remote writes.

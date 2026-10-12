# P083 perk validity submission boundary

Verified source rules: Mini merchant/decor/perks save rejects dates before its China-day tomorrow minimum. Backend ApiCoopController.perkTemplateSave rejects non-null validEnd not after now, explicitly documents date-at-midnight/tomorrow minimum, and sets id to null: this is a create-only endpoint, not historical update. The backend test saveRejectsTodayOrEarlierButAcceptsTomorrow confirms the rule. No new business rule is invented.

Changes: createTemplate request serialization evaluates the current clock and rejects past/today in fixed UTC+8. An optional injected now makes boundary tests deterministic. The normal template editor reviews the request on the tap and shows a translated actionable expiry error if rejected. Preview and existing service serialization evaluate again; a draft opened before midnight cannot bypass the boundary afterward. Existing disabled submit/approval gates stay unchanged.

Historical CoopFlowPerkTemplate initialization and all read services remain unchanged. MerchantPerkValidityDraft.value preserves its original unedited value; explicit calendar edits already enforce tomorrow and remain unchanged. No update-template operation exists here; attaching/deleting templates and unrelated mutations retain exact behavior. No blanket age check in decoding or model initialization, no automatic correction of historical data.

No new App/Core file needs PBX registration; the new CoreTests file is picked up by the existing SwiftPM test target. PBX is untouched, preserving the independently handled branding-file rename. Full after lives in /tmp. Existing P087 and all prior sealed packages remain unchanged.

Validation: focused structure, syntax, Mini source behavior evidence, and 12 authored Core/fake-transport boundary cases. Native Swift/Xcode tests are NOT_RUN in this environment. No production request was made.

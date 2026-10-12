# P083 perk-template validity calendar

Normal route: Merchant → Cooperation workflows → New perk template → Valid until → calendar → choose/clear → confirm → local result in the same form → existing immutable request preview. This is the complete date-selection subflow, not activation of template saving.

The picker uses the source's fixed UTC+8 Gregorian date and yyyy-MM-dd wire value. Edited dates must be tomorrow or later; applying rechecks the clock so a midnight rollover cannot accept a date that has become today. Clearing maps to the existing nil/null request field. No-op and cancellation preserve old/manual text exactly. Dirty closing supports keep editing or discard.

The captured account/session, raw date bytes and all sibling form strings fence late actions. Old sheet callbacks cannot dismiss or apply a newer selection. Background retires the local picker. Result feedback is bound to the matching current form context. No backend call occurs from this subflow, and the existing local preview's disabled submit button remains disabled.

A pre-existing issue is handed to the root: CoopFlowPerkTemplate validates format but not the source's tomorrow lower bound. This feature does not change the old constructor, fallback text field or dispatch policy.

Swift/Xcode/XCTest and real-App sheet/calendar regression were NOT RUN. Core and AppUnit tests are authored; Python structural contracts, real-Mini record-only VM cases and Swift syntax parsing are supplementary checks. Original sealed packages and unrelated host bytes are preserved.

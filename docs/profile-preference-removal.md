# P107 selected-preference removal

Base: `96d727404a966cd3b3d2437c79449046beda560f`, with the three sealed field-edit → case-portfolio → contact-QR afterimages as explicit unsubmitted dependencies. The ProfileEditView preimage is `546ae33dc0cb73c3b9079f10d46702d78618fd99e4015b1829d5ad9bdd0d71a8`. The parent must preserve the newer central body decomposition when merging this increment.

## Verified missing operation

MASTER v10 P107 lists removeCategory. The approved Mini source at `f859cd6e2618f618a53f5cd33949259828e86313` removes the selected category ID and matching display rows locally; saveInfo sends selectedCategoryIds.join(',') through the existing profile update.

The prior native profile page shows only the selected count. Its existing ProfileRoutePreferencePicker must successfully fetch the current discovery catalogue and displays rows only from that catalogue. There is no separate route to remove a selected ID that is visible in the self response but absent from the current catalogue, or to manage selections without fetching that catalogue.

This increment adds that selected-item operation. It leaves the existing add/change catalogue picker untouched and makes no claim to recover a category the self response itself omits. “Unavailable category” fixtures mean selected IDs absent from a current catalogue, not proof that production retains every deleted category.

## Complete user operation

Account → Edit profile → Manage selected preferences.

- Existing selections come from the captured page draft, otherwise the self snapshot's tagIds. No catalogue or media request is made.
- Rows show categoryName from the existing self response when available, and always show the category ID. Missing, malformed or ambiguous labels fall back to a generic category label and ID.
- Remove, Restore, Clear all and Undo removals change only this sheet's scratch selection. Original ordering is retained.
- Cancel or swipe dismiss leaves the page draft untouched. Done stages only an ordered subset of the captured selection. A no-op preserves nil/raw tagIds bytes and any existing staged selection.
- The whole-profile review shows the proposed preference IDs or an explicit empty selection. The existing Save flow serializes tagIds and verifies the returned selection.
- After a verified save, reopening uses the new snapshot. An old sheet action cannot restore an earlier server selection.

Only an ordered subset is accepted, including empty and unchanged. This is not a replacement category-ID input. Addition, reordering, duplicate/nonpositive IDs and malformed persisted strings are rejected. A malformed stored selection is visibly unavailable rather than silently dropping unknown tokens. Other profile edits remain available through their existing routes.

## Existing contract and safety fences

UmsMemberUpdateDTO has String tagIds; the authenticated controller obtains getAppUserId and applies the existing tag update to that member. The mapper accepts an explicit empty string. SelfMemberVO exposes sysCategoryList, which the existing native decoder already converts to tagIds if the explicit tagIds field is absent.

New preferenceNames and payload preferenceIDs are display/review metadata only; neither is encoded. No endpoint, adapter, account scope, token flow or production permission is added. Local staging retains the existing editor UUID, account/epoch, viewer revision, model/draft generation and exact snapshot fences. The coordinator's existing preference-conflict checks before review and write, acknowledged readback verification and unknown-result lock are unchanged.

The feature uses no image reader. Existing case/QR viewer entries remain pending authorized personal image-reader injection and are not newly claimed as usable previews.

## Integration and verification

Registration/localization: PENDING_PARENT_INTEGRATION. New sources and 11 bilingual localization keys are listed in the fragment; shared project and catalogue files are untouched. One prior source-only assertion is narrowed to permit routePreferenceIDs assignment only inside the new explicit preferences branch; ordinary text branches remain prohibited from modifying preferences. Its preimage and scope amendment were recorded before that test change.

Apple: NOT_RUN. Core, AppUnit and UI cases are authored but not compiled or executed on this machine. Focused source checks, static mutation sensitivity, real Mini synthetic execution, exact backend source seams and incremental patch roundtrip are distinct checks, not a native-runtime or CI-green claim. No production profile write is performed. Existing compiler timeout/CI work stays with the parent and sixth line.

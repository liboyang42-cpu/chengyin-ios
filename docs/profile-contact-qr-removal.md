# P107 contact QR removal and local undo

This third incremental slice starts at Git `51d3e24de92427a777f8690f847cec39971b041a` plus the sealed field-edit → case-portfolio afterimages. It adds the missing contact-QR management action from MASTER v10 P107. Existing portfolio paging, previous/next, zoom and close were already connected by the second slice and are not reimplemented.

## Exact supported contract

Mini ref `f859cd6e2618f618a53f5cd33949259828e86313`:

- openPop3 copies the current wechat image reference to scratch.
- deleteWechat clears scratch, cancel3 discards it, confirm3 stages it into the page.
- saveInfo sends the resulting wechat with the existing whole-profile payload.
- UmsMemberUpdateDTO and SelfMemberVO contain String wechat. The authenticated controller uses getAppUserId(), copies request.getWechat() into the current member, and the mapper updates wechat only when it is non-null. Empty string clears it.

This implementation is deliberately clear-only. There is no new-reference input, photo picker, upload operation, endpoint, production grant or actual profile write in the development checks.

## User flow

Account → Edit profile → Contact QR code → Manage QR code.

- Existing QR: the viewer entry is available, along with Remove QR code.
- Remove marks only this sheet's local choice. Keep original QR code reverses it before staging.
- Cancel or swipe-close leaves the page draft untouched.
- Done stages only a boolean clear proposal. Reopen begins from the staged choice; keeping the original and choosing Done removes that proposal.
- Review profile changes explicitly identifies contact-QR removal. Only the existing full-profile confirmation can save it.
- After a known successful save and empty-field readback, the QR is absent. A stale prior action cannot revive it.

## Preservation and conflict handling

`ProfileEditDraft.removesContactQR` is clear-only intent, not a URL. The payload preserves the exact snapshot wechat unless an effective removal is proposed; removal sends only `wechat: ""`. Review metadata is excluded from JSON. An already-empty QR is a no-op.

Local confirmation validates the existing unique editor ID, identity/epoch, viewer revision, model generation, draft revision, complete draft and exact snapshot. Even the shared string-stage helper rejects every QR value except empty or the exact original bytes.

Review checks the original QR against a fresh self read; the final prewrite read checks it again byte-for-byte. A concurrent or Unicode-only source change rejects removal. Existing name, introduction, case description, casePics, avatar and preference behavior is retained. Avatar staging/discard and draft fingerprints include the removal intent.

Known acknowledgment with nonempty readback stays locked until an exact empty readback. An unknown write stays locked even when later readback is empty; checks never repeat the POST. Rejection and failed refresh preserve the local removal proposal.

## Image loading limitation

Viewer entry connected; actual image loading: PENDING_AUTHORIZED_PERSONAL_READER_INJECTION.

The ordinary Account→ProfileEditView call does not supply a personal image reader. The visible AppSession reader belongs to a merchant-review authorization chain; it is not borrowed for this feature. The shared preview reader therefore remains disabled by default. This is not a claim of real image preview availability. The same limitation remains for the prior casePics viewer.

The QR preservation/clear/save contract does not depend on downloading the image. An approved personal reader may later be injected through the existing optional parameter without changing this feature's write scope. The synthetic `.invalid` fixture checks viewer navigation only, never real image pixels or production image requests.

## Integration and tests

Registration/localization: PENDING_PARENT_INTEGRATION. See the registration fragment. The parent must retain its newer body decomposition when merging ProfileEditView; this slice does not fix existing compiler-timeout diagnostics or shared CI.

Apple: NOT_RUN. Core/AppUnit/UI test cases are authored but not compiled or executed here. Focused source checks, mutation sensitivity, original Mini synthetic execution, exact backend seam verification and before/after patch replay are separate evidence. No native runtime, complete personal-domain migration, live readiness or CI-green claim is made.

Both earlier delivery packages stay sealed and byte-identical. This increment changes only the paths recorded before implementation in START and the matching afterimages.

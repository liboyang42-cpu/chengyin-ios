# CARD one-shot receipt and in-game reveal

Source-only App slice; no mini, backend, production capability, remote branch or CI change.

## Source contract

Private chengyin `4b0248cbc00e9e943eba8b43819afb623a87b942`:
- AdvancedGameRuntimeServiceImpl.finishPendingCardMint returns optional top-level `objectCard` after committed photo judgement; subsequent state reads omit it.
- `pages/play/utils/playkit-view.js` buildPhotoCheck accepts this receipt independently of configuration.
- `playkit/index.wxml` uses a CARD-specific presentation; ordinary photoCheck stays separate.

## Implementation

PlayAdvancedState retains a bounded, validated optional ObjectCard using the existing collection model. Invalid/missing card data does not undo committed game completion. A separate ephemeral cache only accepts an actual SUBMIT_PHOTO_CHECK response from a request originating in CARD mode, with matching session and advancing version. Owner/session/node/version are bound; refresh can retain but cannot mint a card. A changed owner/node/mode, backwards version, revoked result or explicit rejection (including 403/404), disabled or unauthorized service clears the cache. Request lifetime prevents late delivery after dismissal from restoring the reveal.

CARD presentation uses the existing camera/upload/review controls, a processing state, actual card/title/caption/server frames, permission-gated bounded media loader and explicit no-receipt/failure states. It does not infer successful minting from `passed`, does not create rotation frames or a 3D model, does not replay a photo just to recover a card, and does not modify the collection feature. Frame controls honor reduced motion and accessibility adjustment. New strings are English/Simplified Chinese.

## Boundaries

- No normal-root write grants enabled; artwork uses only existing approved hosts converted to restricted HTTPS origins.
- No persistent receipt storage; a dismissed receipt can still be found through the separately authorized existing collection flow.
- This is semantic receipt/flow parity, not a claim of the mini canvas dissolve animation's pixel parity.
- 9 cache/decoder and 6 coordinator XCTest methods are authored but UNRUN here.
- No Swift/Xcode compiler installed. Tree-sitter and Python contract checks are supplementary. Simulator/device screenshots, actual camera/permission transitions, VoiceOver/Dynamic Type, late response UI timing and real backend minting remain NOT_RUN.

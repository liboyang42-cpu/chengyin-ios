# P127: merchant coupon feature → owned coupon wallet

## User action and existing destinations

The retained P127 place-detail component's `openFeatured` opens an activity for numeric `featuredType == 1`; numeric `featuredType == 2` opens the player's coupon wallet without an ID parameter. The native roam detail already handled the first branch. This slice adds the missing second branch to the ordinary roam → place → merchant feature entry.

An explicit “Open coupon wallet” tap now opens the existing `AccountCollectionCouponsView`. Its existing authentication, configured/unavailable, loading, empty, error/retry, search, filter and coupon-detail states are reused. The wallet is the current user's collection. A merchant feature ID is never treated as an owned coupon ID, and opening the wallet does not claim, issue, redeem or reveal a redemption code. No new endpoint, reader implementation or production grant is added.

The activity branch stays separate. Missing, unsupported or string-valued feature types do not open the wallet. The existing decoded feature must be displayable, the loaded node and merchant must agree, and the map place, full loaded payload and read snapshot must still match when tapped. A missing wallet factory shows the existing unavailable message. Merely viewing a feature or constructing the destination factory does not read the wallet.

## Navigation and session lifetime

The root supplies a session-bound wallet factory through `RoamBrowserView` into `RoamItemDetailView`. Accepted wallet navigation retains the exact read authority across the normal push. New read snapshots, changed node/merchant content, reader/account/area changes or another active navigation reject the old action. The destination observes the app session and checks its original session/content revisions, roam reader identity and collection scope while the place screen is behind it. It uses the same read-only wallet composition as the existing public-merchant feature and explicitly supplies no coupon-code factory.

This is independent of the saved-card Photos increment: none of its share, photo-save, permission or privacy files are changed.

## Integration and verification

The exact new source/test registration list and the one-line root factory handoff are recorded in `docs/roam-featured-coupon-wallet-registration.json`. Existing English/Chinese wallet, changed-content and unavailable strings are reused. PBX, catalogs and CI are not edited.

The focused Python source checks and Tree-sitter parser are supplementary checks, not Swift compiler or app-execution evidence. Core and app-hosted XCTest cases are authored; Swift, Xcode, CN/US builds, simulator/device UI, VoiceOver and live-backend execution remain NOT_RUN in this environment.

After source registration, run `swift test --filter RoamFeaturedCouponWalletSelectionTests`, app-hosted `RoamFeaturedCouponWalletViewTests`, and an unsigned build. In the ordinary UI, test a named type-2 feature both with and without `featuredId`, a type-1 activity, unknown/missing types, unavailable wallet reader, empty/error wallet, returning from wallet detail, rapid taps and reader/account/area changes while pushed. Check English/Chinese, large text and VoiceOver. Existing frozen-source checks and aggregate CI remain central-integration responsibilities.

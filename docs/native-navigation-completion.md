# Native navigation and evidence completion

## Scope and source evidence

Original native implementation for five bounded page records, compared with Flutter `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`. This is static implementation evidence, not completed product, device, backend or visual acceptance.

| Source record | Native normal entry and implementation | Presentation/state decision |
| --- | --- | --- |
| `lib/feature/play/player_game_module_views.dart#_ScanEvidencePage` (scan return at 1275–1293, photo upload 1297–1325, scanner 1371–1419) | `PlayExperienceView` → `PlayPlayerSessionView` → `PlayerTaskEvidenceView`; `PlayerTaskEvidenceTarget` freezes account/session/activity/node/taskCode/revision and constructs `PLAYER_SUBMIT` | Evidence is pushed within the player's navigation. Camera and photo-library capture remain the runtime host's modals, avoiding two simultaneous presentation owners. Manual code entry is explicitly labeled and never claimed to be camera evidence. Upload and submission have separate reviews. Dismissal/background clears local evidence. |
| `lib/core/router/route_error_page.dart#RouteErrorPage` (14–37) | `AppSession.receiveNativeURL` → `NativeEntryIntent.routeError` → `NativeRouteErrorView` | Native error destination offers Close and Home, never prints the raw URL/exception and does not present a useless retry for an unsupported route. |
| `lib/feature/p3/badges/badge_detail_page.dart#BadgeDetailPage` (10–128), route `/badge` | Normal badge wall toolbar → `BadgeRouteEntryView` → `ObjectBadgeRoutePreview`; approved-origin native URL route also resolves a typed badge query | Lightweight dismissible detail retains existing static style/rarity semantics. Query metadata does not confer ownership or an earned badge. The form accepts documented relative paths, not unapproved external hosts. |
| `lib/feature/team/team_pages.dart#TeamJoinPage` (722–1012), route `/team/join` | Normal team list → `TeamInvitationEntryView`; session host passes typed invitation to root-owned `NativeEntryLandingView` → `SessionTeamDetailView(.invitation)` | Invitation survives initial guest login in a root sheet outside account-keyed tabs. Account replacement dismisses the pending root entry. Existing exact team lookup/join review/readback and recovery remain authoritative. `fromTeamId` is validated navigation context, never join authorization. |
| `lib/feature/coupon/coupon_code_page.dart#CouponCodePage` (25–601), route `/coupon/:id/code` | Owned coupon list → metadata detail → explicit `CouponCodeView` → `CouponCodeCoordinator` | Distinct from metadata. Review precedes temporary code issuance. Cancellable active-screen cadence renews at receipt expiry and checks status every 5 seconds. Owner/role/namespace/epoch change, disappearance, background, 401 and 410 remove credentials; server terminal states cannot regress. |

The coupon implementation reuses `OrderLifecycleRequestContract.issueCoupon` (`POST api/coupon/qr-token`, **couponHistoryId**, never couponId) and `OrderLifecycleService.couponStatus` (`POST api/coupon/status`). Flutter `coupon_api.dart` 189–233 and `coupon.dart` 158–194 provide issuance/status and optional token fields. Its merchant verification contract accepts the exact scanned token. Core Image locally encodes only that server-issued token. When a receipt supplies only a server QR image URL, an explicitly approved HTTPS image host and an enabled adapter are required; the URL is never encoded as a substitute credential. The metadata-only wallet and `OrderPassMetadata` are not claimed as CouponCode parity.

The private current mini-program was read only to verify business intent: strict status 0–3, bounded lifetime, owner matching, stale-response invalidation and terminal monotonicity. No private implementation, assets or raw source are included in this packet.

## Safety and lifecycle

- Production coupon issue/status/media enablement is false and image-host allowlist empty
- External native-link origin allowlist remains empty; no schemes, Associated Domains or entitlements are registered
- Existing camera, photo upload, gameplay commands, team writes and live configuration grants are unchanged and remain off
- PLAYER capture reuses `PlayDeviceCaptureCoordinator`; an uploaded server HTTPS URL, including extensionless/signed URLs, is the only accepted photo submission path. No editable URL field manufactures photo evidence
- Coupon receipt tokens/pixels stay memory-only, privacy-sensitive and unlogged. Rendering is not redemption, merchant authorization, ownership verification or proof of entitlement
- Source lists can be opened without minting codes. Code issuance requires a separate explicit review
- No live backend, camera, location, real coupon generation/redemption or external service request was executed for this work

## Integration dependency

The PLAYER photo-library button uses the already-integrated `playkit-v4` interface: `PlayDeviceCaptureCoordinator.supportsLibraryPhotos` and `capture(_:photoFilter:cameraFrame:usePhotoLibrary:)`, with the corresponding `SessionPlayRuntimeView` library modal host. Integrate this packet after that packet (or its later revisions); do not add another provider or camera host. Background clears evidence; transient inactive phase from an OS permission prompt does not dismiss the capture route.

## Verification

- `check_native_navigation_completion.py --flutter-source <audited checkout>`: 19/19 bounded static/source assertions PASS
- `check_scaffold.py`: project structure, localization and deterministic regeneration PASS
- Existing `check_player_journey_screens.py` and `check_play_runtime_hosts.py`: PASS
- Pinned supplementary Tree-sitter parser: PASS for changed Swift files; syntax only
- 28 new Core XCTest methods and 4 new XCUITest methods authored
- Swift compilation/XCTest execution, simulator/device UI, visual/accessibility and live acceptance: **NOT_RUN for this packet**

The explicit debug harness `--native-navigation-fixture error|coupon|player|badge|team` bypasses production AppSession. All fixture values are original, synthetic and non-redeemable.

## Remaining acceptance gates

Apple compile and test execution must run after integration. Then manually review keyboard dismissal, nested route return, Close/Back, interrupted account restoration, repeated entry, background/foreground, Dynamic Type/VoiceOver and QR contrast/quiet zones. Real domains, deployment read/write grants, camera/library permission behavior and backend-issued QR/token verification require separate acceptance. No five-page increment is a claim of complete parity.

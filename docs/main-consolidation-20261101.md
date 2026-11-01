# Native iOS main consolidation — 2026-11-01

This candidate consolidates the existing public `chengyin-ios` work into one maintained `main`. It is a source integration, not a release or business-acceptance certificate.

## Sources and preservation

- Reviewed source inventory: 151 public remote branches and 74 open pull requests.
- Integration base: `cf971f039304810b6e815944556375f352d55adf`; previous main: `a8d387e206ed3994b6d265b3618db0c293f6ec15`.
- Git ancestry reduced the product sources to 46 independent tips. Shared-file conflicts were reviewed separately; an older branch was not allowed to erase newer permissions, lifecycle handling, navigation, or recovery behavior.
- `work/native-73e-file-transfer` is retained as historical transfer evidence. Its duplicate root catalogs and old project snapshots are not runtime product changes.
- Existing source branches remain provenance. Subsequent development and checks use `main`; a pending or historical PR is not another current product version.

## Integration repairs

Core fixtures preserve nullable schedule times with distinct IDs, refuse unverified message previews, and use stable identity for the permission-denied scenario. App tests use the existing foreground-scene host and valid merchant reply snapshots. Test expectations follow the actual complete localized integer formatting.

Merchant workbench refresh is owned by the stable parent view. Initial loading, manual refresh, and child return share one fresh-access path; old private rows are cleared before approval readback. Revision, cancellation, and permission checks remain between asynchronous steps.

Map integration retains distinct story-node identity and parent IDs. Theme and story layers require an explicit boolean public-read capability, authoritative version and state, and existing coordinate, area, pagination, identity, and action checks. The older map caller conservatively refuses the new story-node detail type; the dedicated verified reader owns that route.

The source merge preserves both order readback and optional support lookup, and retains both the existing ledger and the independent settlement overview. Source helpers and unapplied composition fragments do not establish a working backend path. Undocumented endpoints or unresolved capabilities remain unavailable.

## UI direction

Preserve the existing native design and components first. Use the mini-program to cross-check business content, fields, copy, and rules; adapt structure and interaction to the App. SwiftUI and UIKit navigation, lists, forms, sheets, and controls should follow the native platform. Messaging and other App-specific experiences are reviewed for their own user journeys. WeChat navigation geometry is not a layout constraint for this App.

Visual findings require screenshots from the candidate being reviewed. The current CI is configured to export 26 named synthetic screenshots covering discovery, tickets, messaging with the keyboard, merchant forms and confirmation, empty/error states, and large-text presentation. Those images must be inspected; passing XCTest does not itself establish visual quality, VoiceOver support, or physical-device behavior.

## Verification and publication boundary

The current-source ledger is regenerated after integration. Exact old-main test migrations and individually reviewed historical hash bindings are recorded rather than using a general test-deletion waiver.

The workflow uses GitHub-hosted runners and matrix `max-parallel: 20`. A dedicated UI-build job produces one same-run artifact. UI shards can start when that build finishes, independently of Core and AppUnit execution. Final aggregation still requires successful units, UI build, every selected UI result, and full-mode platform checks at one SHA, run, and attempt.

This document does not claim a successful final cloud run. Its run/check status must be read from the candidate's GitHub checks and integration PR. Signing, TestFlight, production activation, real identity providers, real payments, physical GPS/camera behavior, and business acceptance require their own evidence.

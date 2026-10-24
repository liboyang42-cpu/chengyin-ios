# Ordinary template authoring entry lifetime

Base: `13c5be211e7e03e2f447e2e061840917fab9846b`, `migration/native-ios`.

The ordinary template editor entry now allocates a navigation occurrence UUID and retains its factory result with `StateObject`. This is entry-lifetime hardening, not evidence of a pre-existing draft-reset bug: `AppSession.templateAuthoringEditor()` caches coordinators and `TemplateAuthoringCoordinator.open(seed:)` returns unless its state is idle. The deferred factory makes the once-per-destination lifetime explicit.

The concrete missing boundary was same-epoch role refresh. `sessionRevision` contains only `gate.currentStamp`; `templateAuthoringViewIdentity` additionally includes the current role. AppSession explicitly supports account-role refresh without advancing that gate. The old entry was keyed only by sessionRevision and its completion-library closure consulted the live session rather than capturing the original authoring identity. A completed route could therefore remain mounted across a role change. This patch closes that original navigation occurrence and guards its retained completion context. Existing shelf services already enforce their own read authorization; this change does not claim or fix a proven data disclosure.

The editor, existing draft-save receipt flow and existing publish receipt flow share that retained coordinator. The original completion context is retained for the visit. Account epoch or authoring authorization identity changes dismiss the route; a stale retained destination also fails its completion identity check before presenting the editor or owned shelf. Image selection still requires the existing native-selection approval.

Direct own-library and prefab links are unchanged. No adapters, credentials, publication authority, service writes, project registrations or localization catalogs were added. Default production publishing remains disabled by the existing service configuration.

## Acceptance

- Ordinary entry opens the editor once; parent recomputation cannot call its factory again.
- Existing save/publish receipt panels lead to the existing owned library only for the captured owner identity.
- Returning and opening again creates a new navigation occurrence.
- Account/epoch/authorization change closes the occurrence; old completion context cannot become a new user's route.
- Existing unknown-result journal and cancellation behavior remain in the existing coordinators and receipt controllers.

Six memory-only regression cases were added to the existing registered saved-result test file: factory retention, repeated visit creation with a retained service coordinator, permission/epoch/sign-out revocation, the saved-receipt controller route, repeated destination-value construction without eager factory invocation, and same-epoch role refresh after reaching the completed-library state. The owner tests cover the owner contract; the construction test covers deferred initialization only. None establishes mounted SwiftUI state retention or real navigation behavior.

## Verification

Passed: exact baseline Git blob hashes; targeted source review of launch, AppSession factory and existing save/publish controllers; allowed-path and diff whitespace checks; existing project registration references.

Not run: Swift compiler, XCTest, simulator/device App checks and CI. Source-level checks do not establish runtime acceptance or completion of the full product requirement.

This is one bounded completion-navigation gap within the existing template flow. It does not establish full completion of a document requirement or add a new product feature.

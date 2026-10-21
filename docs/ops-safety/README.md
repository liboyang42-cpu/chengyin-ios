# W01 / W09 / W11 client hooks: degraded states, safety copy, local-data audit

Scope: reform plan v9 §15 (W09), §18–§19 (W11) and W01.1, client side only. Code only, no CI run. Swift
was not compiled or tested in this environment (no Swift toolchain on the Linux sandbox); Xcode build,
XCTest, XCUITest, simulator, device and VoiceOver are **NOT_RUN**. Nothing here is wired into the
shipped composition, and no endpoint is added to any reviewed allowlist.

## What exists

| Area | File | What it does | Default |
|---|---|---|---|
| W11.9 layered kill switches | `Core/OpsDegradedState.swift` | Six layers (global, theme, merchant, SKU, node, AI tool), exact targets, and a pure resolver. Preserved services (order query, refund, after-sales, paid fulfilment, support) are never gated. Unread, stale, future-dated or duplicate readouts give `unverified`, never `inactive`. Continuation is blocked only when the server says it affects existing operations. | Not wired |
| W11 fixed copy | same | §19 runbook incidents mapped to fixed bilingual copy and existing preserved actions. The copy states no times, compensation, refunds or prices. | — |
| W11 deadlines | same | `OpsDeadline.run`: a timed-out read uses fallback copy, a timed-out AI request uses the scripted fallback, and a timed-out **write is an unknown outcome**, never a failure. The policy defaults to `.disabled`, so each service keeps its existing timeout. The plan's 8 s AI figure is kept as an unreferenced proposal; the backend already enforces 8000 ms (`ai.model.timeoutMs`). | `.disabled` |
| Existing server contracts | `Core/OpsServerReadouts.swift` | Decoders for the existing anonymous `GET api/status` (ServiceStatusVO) and `POST api/config/features`, plus the mini-program write-outcome rule (no status / 408 / 5xx = unknown). By default, status readouts only inform. A feature flag can only narrow a capability, and a missing or unread flag is OFF, the same as in the mini-program. | Not in any allowlist |
| W09.5 AI identity | `Core/SafetyDisclosure.swift` | Per-surface disclosure that reuses the mini-program's npc-chat scope lines and draft label, plus the boundary that AI cannot commit prices, stock, orders, rewards or redemption. | Component only |
| W09.6 outgoing text | same | Detects likely mobile, resident-ID and email patterns before text goes to an AI surface. It only asks the user; it never edits, stores or uploads. | Not wired |
| W09.8 offline safety | same | Stopped nodes cannot start. Only a server-provided **no-purchase** alternative is offered; otherwise support is the only action. An unknown status is not `open`. The envelope is a **proposal**; no endpoint exists. | Not wired |
| W09.2–3 presence | same | No evidence kind proves presence on its own. Review outcomes deliberately have no "cheating" case. | — |
| W01 / W11.7 audit hook | `Core/OpsAuditTrail.swift` | Bounded in-memory trail of gate, timeout and fallback decisions with a local correlation ID. It has no free-text fields, does not persist and does not upload. | Not wired |
| Views | `App/OpsSafetyViews.swift` | Gate notice, AI disclosure, offline node notice, sensitive-text confirmation, and a DEBUG fixture (`--ops-safety-fixture theme|payment|unverified|stopped-no-alternative`). | DEBUG fixture only |
| W09.6 / W01 data catalog | `tools/audit_client_ops_surfaces.py`, `docs/ops-safety/client-data-catalog.json` | A static scan of Keychain, UserDefaults and Application Support stores and explicit request timeouts. `--check` fails when a production store file is missing from the catalog. Purpose comes from source comments. Retention and deletion are marked *pending privacy review*. | Static only |

## Evidence boundaries

- Core tests: `Tests/CoreTests/OpsDegradedStateTests.swift`, `OpsServerReadoutsTests.swift`,
  `SafetyDisclosureTests.swift` and `OpsAuditTrailTests.swift`. They are written but NOT_RUN.
- UI test `Tests/AppUITests/OpsSafetyFixtureFlowTests.swift` is written but NOT_RUN. It is not yet
  registered in `tools/current_ci_manifest.json`; the CI/integration owner registers it.
- `Tests/ContractChecks/test_ops_safety_contracts.py` and `tools/audit_client_ops_surfaces.py --check`
  ran locally in Python and passed.
- The static scan proves only that a store exists in source. It does not prove purpose, retention,
  logout or deregistration cleanup, deployment or acceptance.

## Remaining

- Wiring `AIIdentityDisclosureView` and `AIOutgoingSensitiveConfirmation` into ShopNPC and merchant
  NPC composers belongs to the NPC owners. The existing `shopNPC.disclosure` stays as it is.
- Wiring a status/flags read needs an exact reviewed route in an endpoint approval and an owner
  decision on which statuses block. The backend's `X-Mini-Program-Version` / 426 contract is not
  implemented server-side.
- A backend contract is needed for per-layer switches, node safety status and presence review. None
  exists today: there is no unified kill switch, no support timeline and no manual-override audit table.
- Privacy owners must fill in the retention and deletion fields of the catalog. Minors handling is
  still the agreement text only, with no age gate (W09.7, a decision).

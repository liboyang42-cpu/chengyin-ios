# Saved local route replay (P126/P128)

This independent seven-path leaf is based on commit
6ae3e545b373dd5cddc47356a57d0cb6ee928e70 / tree
dc1573c54487cb5402b083b0ff91d3a98025eca9. It adds replay, replay-again, skip to
complete and accessible progress only to an already-saved local history detail.
The history list, empty-history LiveEntry and optional share card retain their
existing behavior. No permission, location, network, route provider, Run/session
mutation, upload, persistent replay state or automatic sharing is added.

## Source and behavior

MASTER-v10 P126/P128 delegates the session body to the actual Mini component.
Its scene-roam-session WXML binds startReplay/skipReplay and shows segment/progress
state. The real JavaScript cancels replaced/detached timers, uses Reduce Motion,
and advances a maximum of 24 frames at 120 ms intervals. The original Mini route
replay module and four unit tests are the reference; the separate local VM
characterization invokes the actual component methods, not a replacement model.

Native retains its existing normalized, complete saved-route geometry. Revealing
a prefix never changes the coordinate scale or POI positions. Default list/share
callers remain full static sketches; only the history detail mounts controls.
Native does not import Mini's separate 180-point simplification policy, screen
pixel geometry or externally shared snapshot flow. It does not represent replay
as navigation, a current location, a fresh measurement or gameplay completion.

The pure frame plan has at most 24 strictly increasing counts, ending at the
exact segment count. Its intended delay budget is at most 2760 ms; this is a
schedule bound, not an executed device performance measurement. Empty, single-
point and fully degenerate routes cannot start replay. Counts stay nonnegative,
bounded and monotonic, including integer-boundary inputs.

Every request captures its reader object, exact session identity and UTF-8 storage-scope key, configuration,
full record and a presentation generation. Start claims playing state before a
request is scheduled. Repeated taps, old buttons, old frames and old task cleanup
cannot control a replacement. Skip and completion retire the old generation.
Reduce Motion skips scheduling when already enabled and completes/cancels a
running replay when enabled. Disappearance and backgrounding stop playback;
foregrounding returns to a full static sketch without auto-resume.

Detail loading now keys the local read by reader identity and timestamp, masks
stale records/errors immediately, and accepts both success and failure only for
the captured owner. This confines replay to the currently loaded record; it does
not require network configuration for a valid local history read. The existing
RoamHistoryLiveEntry prefix is byte-identical.

## Exact scope

- App/RoamHistoryViews.swift
- App/RoamExperienceComponents.swift
- Core/RoamExperienceMath.swift
- Resources/Localizable.xcstrings
- Tests/CoreTests/RoamRouteReplayTests.swift
- Tests/ContractChecks/test_roam_route_replay.py
- docs/roam-route-replay.md

The shared catalog adds only seven exclusive roamRouteReplay.* bilingual keys.
All prior catalog entries remain unchanged. This leaf has no central contract,
runner, scanner, PBX, Package, workflow or budget change. Parent integration must
compose catalog additions and register exact source/support inverses separately;
this leaf's tests do not claim the unmodified central admission accepts it.
Cancelled map6/P043 and category10 are not dependencies and are not modified.

## Executed evidence and remaining gates

- New public raw-source gate: 14/14 PASS, including exact old-source rejection,
  ownership/lifetime/motion/request/accessibility mutation controls, byte drift,
  CRLF and malformed inverse rejection, immutable LiveEntry and catalog checks.
- Targeted public discovery: 14/14 PASS, without private Mini/MASTER input.
- Five existing Roam source modules: baseline 39/39 and candidate 39/39 PASS,
  with their original assertions unchanged.
- Real Mini existing tests: 4/4 PASS; actual-component VM characterization: 8/8
  PASS, including play/skip/repeat, Reduce Motion, detach and timestamp changes.
- Pinned Tree-sitter 0.26.0 / Swift grammar 0.7.3: four Swift files parse with
  zero ERROR/MISSING diagnostics. This is syntax evidence only.

Seventeen new Core tests are authored and NOT_RUN. Swift type checking, compilation,
XCTest, SwiftUI task/lifecycle timing, Apple UI, VoiceOver, Dynamic Type and real
rendering/performance remain NOT_RUN. No full suite/full discovery or central
registration run is represented as passing. The frozen packet records exact
source scans, replay and identities. Nothing has been uploaded or deployed.

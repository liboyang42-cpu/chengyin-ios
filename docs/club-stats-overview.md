# P045 owner statistics overview

## Source and preimage

- Independent base: `94bced23ae734bcd8a5e236c8b992294bd15b14a`. No earlier packet overlay is required. Sealed batches 1–9 remain unchanged.
- Master: P045, `MASTER-v10-extracted-text.txt` lines 1652–1655, `loadClubStats`.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`; detail JS Git blob `b49b5fb14caf49d47e971cd93ffd73cd94d8e044`.
- Mini `pages/club/detail/index.js` lines 210–253: `metricInteger`, `metricRate`, `shapeClubStats`; lines 1076–1109: owner-only request and loading/error/ready handling. WXML lines 468–492: four totals, statistic scope and per-project completion rows.
- Verified native gap: generic governance `.stats` rows omitted the dedicated total metrics, supplied completion rates and metric scope.

## Real read contract

The ordinary owner ClubDetail entry passes the existing `ClubGovernanceContext` to `ClubStatsOverviewView`. This screen calls only `ClubGovernanceAccess.read(.stats, scope: clubID, options: [:], check:)`. The existing service performs `access/me` preflight and requires `OWNER`, then posts to `api/stats/club` with `clubId`. No new endpoint, transport, session composition, role grant or write command is introduced.

The accepted same-club snapshot uses only:

- `topicCount`, `participants`, `completed`, `overallRate`.
- `topics[].topicId`, `name`, `participants`, `completed`, `completionRate`.

All project identities are validated before the first five source-ordered rows are displayed. The screen does not sort or derive project count from the visible rows. No project navigation is invented; the corresponding Mini statistics rows are informational.

## Measured zero, unknown and not applicable

Counts are optional nonnegative integral safe numbers. Missing, null, boolean, empty, non-finite, negative, fractional or unsafe counts stay **unknown**, never zero. An explicitly measured zero displays zero.

Percentages come from the supplied `overallRate` / `completionRate` only. A known positive participant count plus a finite supplied rate in 0…100 displays that rate to one decimal. Known zero participants displays an accessible not-applicable dash. Unknown participants or missing/invalid rate displays **unknown**. The client never computes completed/participants, guesses a denominator, infers rate from rows or repairs inconsistent supplied metrics. The display's `/100` is solely conversion from percentage units to the standard localized percent formatter.

This deliberately does not reproduce Mini `Number(null) == 0`. The source oracle records that coercion. Existing native `ClubGovernanceValidation` remains unchanged: a live response missing required metrics is rejected as a read error before this projector runs. Defensive partial projections used by other conforming/injected readers retain unknown fields; this packet does not loosen service validation to obtain partial success.

Scope text explains that only this club's self-hosted projects are counted, excluding accepted projects; player participations are distinct players reaching nodes, not registrations. Source-provided rates remain authoritative. Blank project names use a localized untitled fallback.

## Read and return lifecycle

The screen provides loading, explicit error and retry, pull-to-refresh, refresh, genuine empty project state and native Back navigation. A read clears its old snapshot before a fresh attempt, so old metrics never remain as current after a failed refresh.

A context bind invalidates old visibility permits synchronously without publishing during body evaluation. Each read has a separate generation. Delayed refresh/retry callbacks from a retired context or visibility return before changing state. Identity/epoch, authorization generation, access object, club context and viewer revision fence accepted data; checks run before dispatch and after awaits. Disappearance retires pending reads. No shared coordinator is cancelled.

Large Dynamic Type uses one column for totals; normal text uses two. Project counts have explicit labels rather than ambiguous numeric ratios, and the not-applicable dash has a VoiceOver explanation.

## Integration and verification

`club-stats-overview-registration.fragment.json` lists the new App/Core sources and test files. Merge the 13 bilingual localization keys centrally. PBX, aggregate localization, CI, shared fixture hosts, AppSession, governance service/contracts/validation and existing governance views are unchanged. The ClubDetail owner entry is a separate hunk from earlier merchant and community packets.

Executed in this task workspace:

- 21 targeted structural assertions: PASS.
- Nine source-shape cases and five source read/control flows: PASS in Node using verbatim Mini functions with record/network stubs. The exact source blob was recorded.
- Five changed/new Swift files: Tree-sitter syntax PASS, zero recovery/diagnostics. This is not typechecking.
- `git diff --check`, exact before + patch reconstruction, reverse apply check and all nine sealed-prior SHA checks: PASS.

Authored: 12 Core tests and 9 app-hosted read/lifecycle tests. **All 21 Swift tests are NOT_RUN** because Swift and Xcode are absent. No native build, simulator UI/VoiceOver run, screenshot, real-account request or backend acceptance occurred. The screen uses existing read configuration; this source packet does not claim a live deployment has been enabled.

Native acceptance: owner open/read/back; non-owner access preflight; genuine zeros versus unknown metrics; zero participants; first-five source order; long names and accessibility text sizes; malformed response versus empty; failed refresh then retry; competing requests; leave/reopen; account/epoch/role/region/access changes while a read is suspended; delayed old refresh callback after new context binding.

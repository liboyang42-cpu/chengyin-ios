# P004/P108 own growth overview

## User flow

Account → Public profile → Achievements now offers a **My growth overview** read panel. It shows level, experience, growth points, lifetime check-ins, mileage and consecutive days from the existing approved growth reader. Known zeroes remain zero. Missing or invalid metrics remain unknown. Center and exploration failures have separate read-retry states rather than pretending the user has no history.

Refresh uses the existing overview read model/lifecycle. The panel opens the existing GrowthCenterView and its leaderboard using the same owner-scoped read wrapper. Ordinary AccountView supplies its current social identity and existing growth reader/scope. Guests and other public profiles cannot read the owner's data. No new API, credential, permission, persistence, write adapter or image reader is introduced.

## Source and exact contract

Sole master P004/P108 delegates to `cy-profile`. Approved Mini ref `f859cd6e2618f618a53f5cd33949259828e86313`:

- `subpackageMember/components/cy/profile/index.js`, blob `99008cdb5c877c851f87f68fecac09f27c9eb46e`, `loadGrowthBundle` (921–962) reads `/api/play/growth` and `/api/growth/center`. It uses play level with center-level fallback, center exp/points, and play check-ins/mileage/streak. `fmtKm` formats the existing mileage value without converting meters.
- `goGrowthCenter` (1739) opens `/subpackageP3/pages/growthcenter/index/index`.
- `index.wxml`, blob `a955ea313225063e484fa09e937e0c9899b14ecb`, own Achievements block exposes growth/points/exploration information and the growth-center action.

Native already had a standalone GrowthCenterView and GrowthCenterReading but did not show these six own metrics or that read/navigation chain on the personal public-profile page. This does not replace the earlier earned-medal panel.

## Deliberate contract differences

The existing native `overview()` also reads completed history and leaderboard; that composite service is unchanged. The panel selects only its center/progress fields. It does not invent Mini's monthly ranking, rank delta, weekly points, city scope or statistics response from the native leaderboard. Growth points here are specifically `center.points`, not `rank.me.score`, wallet money or an award claim.

Mini gates the growth bundle as a whole on failures. Native retains successful sibling values alongside explicit section errors. Zero mileage is not labelled no exploration. No empty-history assertion is inferred from one or several zero metrics. Mileage retains the existing native kilometer label and formatting contract. No new imagery or preview availability is claimed.

## Ownership and navigation

The current Account host captures its social identity and growth-reader scope together. A context requires positive viewed member ID, that exact current viewer/role/epoch, matching captured growth scope, both readers configured and the growth reader authenticated. It also captures both reader instances and the social presentation revision, including ABA invalidation.

The wrapper checks this full context before an overview/leaderboard request, after its success and before forwarding errors. A queued destination cannot read a replacement account before the old UI rerenders. The summary retains this wrapper with State and keys the view by full context. The full center and leaderboard share the same wrapper, so their child navigation cannot escape the captured owner. Existing read lifecycle cancellation/retry is reused. No save or arbitrary endpoint forwarding exists.

## Integration

Base `49c68c6420270b0a0cc7ec8d18bc8561f329d796`, tree `4c834dfe65b9bf9b7a7d36ec238cb5fa9b42487c`. The base already contains the seventh author-refresh shared page, whose exact SHA was verified. Do not overwrite base49 seventh fixes with its historical full package.

Exact eighth → tenth → eleventh afterimages were overlaid for this package. Shared AccountView/SocialPublicProfileView beforeimages and 33 overlay paths are recorded. Merge shared changes additively. All previous eleven archives and central editor body/fixture fixes remain unchanged. Existing GrowthCenter services/views/components, AppSession, central project/localization and other lines are untouched. Registration is fragment-only, including five translations and a DEBUG fixture route.

## Verification

24 new source checks, 97 dependency checks, 16 source-mutation probes and 6 exact Mini-method synthetic cases pass. These assertions do not execute Swift. 18 Core + 7 app-unit + 6 UI tests are authored (31 total), using synthetic growth/public readers and the existing read UI model.

Swift, swiftc and xcodebuild are absent. Apple compilation, all native tests, actual push/pop and real-account behavior are NOT_RUN. No user data read/write, user photo or OS permission action occurred. Full before/after images, reversible patch, SHA manifest and evidence are included.

# Invitation first-purchase reward review

## Actual source and missing flow

MASTER-v10 P118 delegates to Mini `components/cy/scene-member-invite-history`; PA01 requires real read/empty/error/return/account-cleanup behavior. Pinned Mini f859cd6e2618f618a53f5cd33949259828e86313 `rewardMap`, `buildGroups`, `load`, `retry`, and actual WXML show a cumulative first-purchase reward total, month reward subtotals or member counts, and an incomplete synchronization state. Native already showed individual rewards and invitation groups, but did not project those totals.

This increment adds that review to the ordinary existing Account invite-history route. It uses only the current invitation model's loaded members and SocialRewardScan. Unknown/partial/inconsistent totals remain waiting for synchronization. The retry reloads both invitations and rewards through the model's existing synchronous captured-permit reset path; the label says so. Existing member-profile navigation, pagination, refresh, error states, private-view protection and cancellation are retained. No new reader, endpoint or optional default-disabled adapter is introduced.

## Totals and scope

- Cumulative first-purchase points: all positive eventType5 records already normalized by the existing scan, including reward member IDs whose invitation page has not yet loaded. Only exact ledger total == fetchedCount can produce a cumulative number. Genuine complete zero displays zero.
- Month reward subtotal: exact distinct loaded member IDs in that displayed month only. It is not a full-month server total. Known partial-scan rewards are explicitly labeled partial. If there are no positive known rewards, show genuine loaded member count, as Mini does.
- Missing scan or contradictory smaller total cannot produce a cumulative number or false zero. Decimal accumulation rejects NaN, negative, overflow and loss-of-precision results. This does not reparse or modify existing individual reward records/scanner behavior.
- Existing month-group keys and invitation model are byte-identical to baseline, apart from view insertion. No timestamp parsing, financial service, currency, wallet balance, redemption or old scanner fix is introduced.

## Current read ownership

New retry uses the existing captured LoadPermit synchronously through model.start. That function checks model owner, visible presentation, bound-reader identity/object/revision/configuration and current authentication before a task can dispatch. The original model remains byte-identical. Buttons disable during load. The review is mounted only below model.matches(reader), and the existing view remains privacySensitive.

The additional owned retry is the third UI model.start call site. START has a dated scope addendum for adapting the existing exact-count assertion from two to three and asserting the new review section. The test's no-unowned-Task and all other guards stay in place. This is new-feature test maintenance, not a historical defect repair.

## Integration and evidence

Base 49c68c6420270b0a0cc7ec8d18bc8561f329d796. Independent of the 13 sealed profile packages; no shared public-profile/editor afterimage is overlaid. Only SocialInviteHistoryView is a shared view; preserve any newer central changes by additive merge. Register new source/tests and seven bilingual keys from fragments. Dedicated synthetic DEBUG fixture only; no real account read or user operation was run.

26 new source checks pass. Four directed existing modules run 28 checks: 27 pass; one known baseline failure remains in SocialAccountSourceTests (localization count expects107, existing114). The same assertion fails in the equivalent base49 tree before this increment; see baseline-known-failure.log. It was not fixed. Sixteen control-validated source mutation probes and seven exact Mini synthetic cases pass. Source checks are not Swift runtime evidence.

29 native tests authored:16Core,7AppUnit,6UI. swift/swiftc/xcodebuild are absent; native compilation, actual iOS behavior, screenshots/accessibility and real-account reads are NOT_RUN. All13 prior seals preserved; precise before/after/patch/replay/checksum evidence included.

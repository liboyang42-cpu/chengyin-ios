# Wallet income record detail

Baseline: `13c5be211e7e03e2f447e2e061840917fab9846b` on `migration/native-ios`.

## Delivered source slice

The normal wallet income list now opens a selected server-returned record in a read-only sheet. Closing returns to the same list and filter. The detail displays the source reason, event, direction, signed amount, currency, optional post-record balance/date, and record identifier. It does not infer payment, payout, settlement or refund completion. Unknown amounts/currency retain the existing formatting policy, and known zero stays zero. No aggregate or additional detail endpoint is invented.

Selections require a successfully loaded income page and bind its snapshot UUID, filter, reader object, namespace, account and authentication epoch. A replacement reader must actually reload even when pagination had ended. Refresh/filter changes and explicit pager cancellation retire old selections. Scope loss and backgrounding dismiss the sheet. Presenting this sheet does not itself cancel its underlying pager. The normal history reader retains its independently issued read approval and role/viewer-revision fence; production grants remain unchanged.

The fixture-only host gains an Income destination. No production write or financial capability is added.

## Acceptance authored

- Eight Core regressions cover exact source row/no extra request, unknown vs zero, changed account/epoch/namespace/logout, refreshed identical rows, filter ABA, non-income/unloaded rejection, same-scope replacement-reader reload, and cancellation.
- One AppSession regression covers real history-reader composition, revoked/replaced read approval and role ABA using synthetic HTTP.
- Two UI regressions cover entry/detail/close/reopen/back and background/return/reopen through the existing offline fixture.
- Existing files are already target inputs; no project or resource catalog change is required.

## Verification limits

Baseline file Git blob hashes and local source/diff checks passed. Independent review is recorded by the integrator separately. No regression suite, Swift type check, Apple build, simulator/device App test or CI was run for this change. Sheet lifecycle, VoiceOver and runtime behavior require future Apple execution. This small source slice does not establish completion of the overall wallet requirements. No payment, withdrawal, refund, reward, deployment or App Store action occurred.

# Post-join read-only detail continuation

After a direct join returns a correlated acknowledged or synthetic completion and its durable journal entry is successfully cleared, the invitation screen exposes Team details without requiring dismissal/reopening. The navigation evidence is specific to that join, target, and captured session. Existing mutation `actionLocked` behavior is unchanged.

The destination gets a separate host-session coordinator, freshly reads the exact team ID and requires `joined == true`. It clears prior roster before every refresh. It is permanently read-only for that coordinator's lifetime: prepare, confirm and outcome reconciliation are blocked, and mutation/invitation-preview/outcome controls are omitted. Journal restore still runs; this route never clears an unknown record. Back and reopen repeat the membership read.

Unknown results, wrong operation/team receipts, failed journal clearing, unrelated successful actions, later synthetic reconciliation, and a changed session cannot establish direct-join navigation evidence. No production transport, capability approval, receipt reconciliation, or backend contract is enabled or changed.

Source reference was checked at private source revision `11be8cb2f09073496f3a7d5130d558da60cf5439`: mini invitation success sets joined and transitions to the exact-ID detail, whose on-show path reads team info. Native deliberately uses an explicit accessible continuation rather than reproducing the 500ms automatic redirect or replacing navigation history. This is read-only post-join continuation, not complete mini detail action parity.

Local Python contract/tooling/scaffold and pinned supplementary Swift parser checks pass. Swift typechecking, Apple build, authored Core/XCTest/UI tests, layout/accessibility and real service acceptance are NOT_RUN in this Linux environment. Offline simulation is not a real membership change.

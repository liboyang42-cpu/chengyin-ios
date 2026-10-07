# Admin management sheet: failure-only synthetic diagnostics

Independent baseline: published commit `7dd74b54a9aff8260198e5c00bc2feaac68337fe`, exact tree `4145c2a180e313844efbc5491e81893ccbe60b93`. This diagnostic patch is separate from the cooperation cancellation patch and all nine earlier feature packets. No existing packet is modified.

## Actual observed failure

Run129 job112729141472 failed ClubOperationsFlowTests.testAdminProfileHasNoOwnerSettingsOrRoleActions at original line85: club.ops.field.name did not exist within the existing five-second wait. It did not reach the subsequent assertions that administrators lack owner settings/member-role actions.

The actual failure screenshot, 73FAA1FE-AD0E-456C-977C-E8C44A108FBA.png, shows the synthetic root Club workspace with its create/manage/account controls and zero writes. No management sheet is visible. The two other UI1 screenshots belong to successful quota cases and are not evidence for this failure. The relevant log records openManage tap at103.71s, field wait beginning110.83s and failure around116s. Earlier startup/fixture discovery was slow, but that does not prove infrastructure failure.

At the exact source baseline, the manage handler simply assigns destination=.club(81), and the admin synthetic snapshot permits profile reads. A denied or failed profile read would still leave the workspace sheet displaying its error. The evidence does not establish a lazy form-field problem, an administrator permission defect, or a specific SwiftUI presentation defect. It lacks whether the handler ran, whether destination was retained, and whether a sheet ever appeared and disappeared.

## Diagnostic-only change

Inside the existing DEBUG-only ClubOperationsFixtureHostView, manage-handler and sheet appear/disappear counters plus destination/visibility booleans are exposed on the existing fixtureNotice accessibility value. The payload includes only the synthetic scenario name, booleans, and request/write counts. It contains no account IDs, tokens, profile text, URLs or real data. The diagnostics are not used to choose a route, grant access, retry a tap or change a timeout.

Only the original line85 assertion receives a lazy failure message reading that diagnostic. Its five-second timeout and the one original manage tap remain. Every later administrator guard, the complete shared tap/reveal helpers, all other UI methods, and production Club code remain byte-identical. Sheet binding, target and access/coordinator injection are unchanged. The DEBUG counters may affect observation scheduling, so their presence is evidence gathering, not proof of a production repair.

Three source checks include negative controls: removing an owner-only field assertion, flipping the owner-setting prohibition, adding another tap or increasing the five-second timeout are rejected. These checks protect the original test rather than make it pass through weaker conditions.

## Remaining acceptance

The original Apple UI failure remains OPEN and UNEXPLAINED. Root/reviewer must integrate and schedule a targeted rerun to inspect the synthetic failure values; this lane did not dispatch a workflow. No new UI method or budget is added. Existing owner/admin/ordinary protections must all remain in the final run.

Swift/Apple SDK build, UI runtime, failure-message observation, new screenshots and any timing/presentation conclusion are **NOT_RUN** here. Parser/scaffold/source checks are supplementary only. No production permission, navigation logic, Workshop, localization, storage, fixture-retention, shared budget/CI, release or real network operation changed.

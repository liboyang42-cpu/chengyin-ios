# PlayKit source reconciliation (v6)

## Retired components are not active implementation gaps

Current mini-program source explicitly records retirement of the orphan `gametimer`, `stickerbook` and `woodfish` families on 2026-09-20. The current dispatcher registrations/branches and the two component directories are absent. Flutter's stale `PlayKitKind.gameTimer` and `PlayKitKind.stickerBook` builders do not justify reintroducing them into the native business flow.

The earlier packet prose incorrectly classified gameTimer/stickerBook as remaining active utility work. `playkit-retired-components.json` corrects that classification with precise evidence. Neither family is counted as implemented, migrated or accepted; both are excluded from the active business-gap denominator. Historical empty action-catalog entries do not enable a screen or an API action.

## Actual verdict versus configuration

Backend `AdvancedGameRuntimeServiceImpl#putChallenge` returns configured `tries` before runtime `attempts` exists. The generic native result row formerly treated either as an attempt count and could show a failed stopwatch result before any attempt. `PlayKitScreenProjection.reportedPass` now requires actual server outcome/attempt evidence; an allowed-attempt cap never becomes a result.

Photo review keeps its distinct branches: degraded has no pass/fail conclusion; explicit successful review can show passed; flagged/fallback uses its dedicated completion wording rather than mislabeling `passed:false` as a failed review; a real retake decision remains a failure. Stale reason text is not shown after degraded or flagged fallback.

Six new Core regression tests are authored. Python checks verify retirement classification against the explicitly supplied mini-program checkout and native dispatch. Those checks are source-level evidence, not Swift/visual/live execution.

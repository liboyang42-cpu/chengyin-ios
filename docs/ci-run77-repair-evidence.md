# Run 77 repair boundary

Exact source: `dd9d58560b954204cc93c9113246f53efff7ad70`.
[Hosted run 77](https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/37109973489) executed all 439 unique UI methods: 436 case passes and 3 assertion failures. It is not an all-green run. Core 3215, app-hosted 76, simulator/CN-device/US builds and secret checks passed.

- Shard 8: SocialAccount's compound disappearance/editor predicate timed out despite the captured complete draft, dismissed keyboard/dialog and enabled Preview. The repair keeps the five-second disappearance bound and exact full-value/existence/enabled assertions as separate observations.
- Shard 8: MerchantMarketing's option row overlapped the synthetic bottom toolbar in the failure hierarchy. No failure screenshot was captured for that old test. Move only DEBUG harness controls above navigation, retain production settlement behavior and add failure capture plus a large-text no-overlap/cancel regression. Runtime correction remains to be verified.
- Shard 5: maximum-text Settings legal navigation failed before reaching the legal page. Separate screenshot-backed investigation supplies the narrow scrolling correction.
- Shard 6: all 48 cases passed, but the xcodebuild process exceeded the 1680-second deadline during finalization. The job remains failed with exit 124. The new process budget is 1800 seconds and job ceiling 37 minutes, preserving seven minutes for setup/export/cleanup. Assertion timeouts and strict deadline failure behavior are unchanged.

Three callers previously used an unrecognized dark-mode flag. Their old runs do not prove dark appearance. Canonical flags and DEBUG descendant environment readback now assert effective root color scheme and text size. This does not prove nested-sheet environment inheritance, actual device settings, or VoiceOver behavior.

## Measured timing provenance

`ci-run77-ui-observations.json` records successful per-case durations and failed case names directly from the ten completed job logs. A passed case in a failed job supplies duration evidence only; it does not make the job successful. The duration profile uses the maximum of an existing successful measurement and a successful run77 observation. Failed case durations never replace measurements. New tests retain explicitly unmeasured estimates and the source inventory still determines every selected method.

All fixes require a new exact-SHA Apple run. Local Python guards and supplementary Swift syntax parsing are not compilation or runtime evidence.

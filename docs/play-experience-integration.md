# Integration checklist

1. Copy additive Core/App/test/docs files listed in the Play slice manifest. Do not replace earlier `PlayContracts`, `PlayReading`, `PlayService`, `PlayProgression` or `PlaySessionView` files
2. Merge localization fragment into Localizable.xcstrings preserving all current keys. Add `playExperience` to DEBUG ModuleFixture routing
3. Add AppSession `playExperience(for:)` with current account/epoch/RegionalSessionStorageScope; retain coordinator and memory recovery stores. Keep PlayExperienceService capability default empty
4. ActivityDetail's runtime entry uses the actual activity ID. It must never substitute topic ID or instantiate a different account's reader
5. Keep all six exhaustive UI shards; regenerate the project, shard inventory, and source scaffold counts. Do not reduce existing test scopes
6. macOS domain-test minimum is 14 for Observation; iOS remains 17. These changes do not assert Swift build success
7. Execute Python source-contract/static checks. Mark `swift test`, Xcode build, XCUITest, device and live backend `NOT_RUN` until the Apple/approved environment actually executes them

Follow-up files PlayPrefabRuntime and dedicated director/prefab views are not part of the first integration until their own tests and bridge validation finish. The runtime store must use `prefab-runtime.v1`, and must never read `prefab-preview.v1` or accept preview photos/synced flags as live proof.

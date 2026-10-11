# P005 · A usable local Reduce Motion switch

## Source-backed missing interaction

Master v10 P005 / PA04 lists `openRoamSettings` and `toggleReducedMotion`. P130 caption authoring is already a separate sealed delivery. The bounded follow-on inspection chose this existing local-preference action, not another camera gate, map adapter or incomplete exchange destination.

At retained private Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:

- [Roam page](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/pages/roam/index.js), blob `08f9a615629f801f2a9aec444d1971cdc4168b83`: `toggleReducedMotion` writes the Boolean preference, settles an existing source zoom animation when reducing motion, then updates the visible switch.
- [Roam view](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/pages/roam/index.wxml), blob `822a08d78b4c17a7a1b807d49d082112ffe1a4a2`: the settings sheet exposes a real switch with an accessible checked value. It explicitly distinguishes that local preference from permission settings.
- [Shared motion preference](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/utils/motion-preference.js), blob `267cf0b0c67ab457b6434bc668abf48a27b1d2f9`: one app-wide device preference, false by default, read through the current key with a legacy fallback.

Native base `96d727404a966cd3b3d2437c79449046beda560f` already has the `QuestifyReduceMotion` policy and many consumers, but only reads the iOS environment and a DEBUG fixture flag. The ordinary roam handbook has no local switch. This slice supplies that missing user choice through the existing animation policy, without reimplementing consumers.

## Ordinary behavior

- Roam → existing handbook → Display and motion: a native Toggle changes a local Boolean stored by SwiftUI AppStorage under `chengyin.preferences.reduceMotion`. It is usable without network, an authorized reader or a hardware grant.
- The default is false. The effective policy is **iOS Reduce Motion OR local preference**. Local off restores following iOS; it never forces animations when iOS has requested reduction.
- The existing DEBUG override remains DEBUG-only and can still force reduction. It is not an iOS setting change or evidence that the real system preference was tested.
- The visible effective-state text and system-enabled explanation distinguish the local switch from the resulting behavior.
- This is an app preference shared across supported custom animation consumers, not private account data. Page recreation or account changes do not intentionally reset it. The Mini's own keys are provenance only; native does not pretend it can read the WeChat storage sandbox.
- Existing card press feedback, route replay and other `@QuestifyReduceMotion` consumers read the combined value. The saved roam replay changes only its input from the direct system environment to QuestifyReduceMotion. Timing, business actions and existing Reduce Motion fallbacks remain unchanged. A replay consumer already reacts to a policy change by retiring its frame request; this slice adds no timers or map behavior.

## Boundaries

No root composition, permission prompt, iOS Settings link, GPS, camera, HTTP request, history clear, coordinate conversion, map supplier, production read configuration or grant change. No global system preference is written. No runtime data or actual device setting was changed while developing this package. No prior delivery is overlaid or changed.

The central owner receives one Core app-source registration, one UI-test registration and six EN/zh-Hans entries in `roam-reduced-motion-registration.json`. Package discovery covers the pure Core source/tests automatically. No central PBX, catalog or CI files are edited and no new test framework is introduced.

## Verification and remaining gate

- Three Core XCTest methods authored: default follows both system states, local true works with either system value, local off preserves the system value.
- Two XCUITest methods authored using the existing offline roam host/helpers: ordinary unconfigured handbook switch + relaunch persistence, and Chinese maximum text/dark mode with the existing forced-reduction fixture. Each preserves/restores the original local preference; no system setting is modified.
- Native XCTest, Swift typecheck, Apple app build, simulator, VoiceOver and physical-device execution: **NOT_RUN**. The current dot computer has no Swift or Xcode toolchain.
- Six changed Swift files receive supplementary Tree-sitter syntax parsing. This is not Swift typechecking or Apple API validation.
- Eight retained Mini helper/action cases run with inert storage and animation stubs. These establish the source behavior only; they are not native tests.
- Directed source assertions, clean-base SHA checks and reversible patch replay are recorded in the delivery evidence.

## Apple acceptance handoff

After central source/test registration and localization merge, run `ReducedMotionPreferenceTests`, existing `RoamRouteReplayTests`, `RoamReducedMotionFlowTests` and an unsigned app build. Check both real system values crossed with both local values, including system changes while the app is active, page Back/reopen and app relaunch. Confirm supported card/replay fallbacks, EN/zh-Hans, VoiceOver Toggle state and text up to accessibility maximum. Keep normal action buttons usable with motion reduced. The source does not authorize enabling previously gated map animations or live business/device capabilities.

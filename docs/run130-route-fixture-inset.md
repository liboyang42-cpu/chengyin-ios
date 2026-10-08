# Run130 fixed synthetic controls inset

Base11800193/tree30cd. UI21/job112840749880 executed10 complete methods:9passed,1failed. The map refresh journey failed before dispatching its synthetic refresh, in the unchanged bounded reveal helper.

Full log and actual screenshot451B39FB-B9B9-4D15-81AE-2C69B0776921.png show the Journey task with its fixed synthetic controls at the bottom. AX records app height912 and controls y834…878. The existing helper conservatively excludes40points at the bottom, so its bottom boundary872 cannot contain this fixed control. Repeated scrolling moves the body, not this safe-area inset. This is not evidence that production refresh/navigation failed.

The one-line DEBUG fixture candidate adds8points bottom padding after the existing controls identifier, retaining44point minimum control height. This aims to move the inner menu into the helper's existing viewport. Original tests, helper, controls/action IDs, account/scope fixture logic, all production navigation, all budgets and CI remain byte-identical. No additional waits, gestures, fallback locators or real service actions are introduced.

The screenshot ZIP artifact11490975467 was obtained through the supported connector; initial transient502 failed, a single same-URL retry succeeded. Its SHA2562cb7e23caf336f1203720b3b3dfc6df0f551b3993fcfb9466a3ed34f5686906a matches the original job upload record. All three original PNGs were visually inspected, with no image modification.

This candidate has not run on Apple. Native AX bounds after the padding must be verified by the unchanged original journey in a future reviewed CI batch. The current run130 is not cancelled or replaced by this work.

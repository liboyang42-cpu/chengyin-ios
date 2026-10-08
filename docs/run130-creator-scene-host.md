# Creator hosted-test scene ownership

Base: published 11800193a5f5057e6598b4e46e8ecb4a98e4572a / tree30cd0ace4249489a6ab22cc60f86a49edfb00bcf. This candidate is independent of all UI follow-up packages.

## Evidence and bounded hypothesis

In run130 job112840744231, the three Creator hosted methods reported rootWindow=false, hostWindow=false, rootAppeared=false, hostAppeared=false, topMatches=true and idle=true. Their setup used UIWindow(frame: UIScreen.main.bounds) without associating a UIWindowScene. The proposed test-host correction uses exactly one currently connected foreground-active UIWindowScene. This is a supported hypothesis, not an Apple-verified explanation or fix.

Apple documents UIWindow(windowScene:) as creating a window and associating it with the specified scene: https://developer.apple.com/documentation/uikit/uiwindow/init(windowscene:). The windowScene property associates or removes a window from its scene: https://developer.apple.com/documentation/uikit/uiwindow/windowscene.

## Exact scope

Only the three existing hosted methods in two AppUnit files change window construction and cleanup. A test-only MainActor helper resides in the existing Consent test file, guarded by DEBUG. Missing or multiple foreground-active scenes throw an explicit XCTest failure. No scene is synthesized; no test is skipped. The frame uses that scene's coordinate space. UIKit alone delivers appearance callbacks; no manual onAppear or transition call is added.

Cleanup hides and detaches the owned window. It restores the captured prior key window only if the owned window was still key and the old window is still present, visible, normal-level, rooted, and associated with the same connected active scene. A new key window is not overwritten. No production source, permission, network service, UI test, runtime budget or workflow changes.

The existing 5-second waits, business assertions, probe declarations and every other method are byte-preserved under an exact inverse of these three setup hunks and the new helper. Two legacy source-check reads use that verified inverse; all old assertions and the old probe hash remain unchanged. The new checker binds complete before/after SHA256 values and the complete contract SHA; negative controls reject missing/duplicate setup, altered scene selection, skip substitution, cleanup weakening, longer waits and assertion deletion.

## Open obligations

Swift type-checking, Apple framework behavior and the three hosted outcomes remain NOT_RUN for this candidate. The Coop compound covered/current assertion and unfinished Owned navigation watchdog remain separate unresolved cases. The existing run130 is not changed or cancelled. No source or test claim here establishes those other failures' cause.

# Validation

- Static source/contract assertions: PASS, 133 (rerunnable via Tests/ContractChecks/check_shop_npc.py)
- Core XCTest cases authored: 23; execution NOT_RUN (Swift compiler unavailable)
- UI XCTest cases authored: 4; execution NOT_RUN (Apple runtime absent; fixture mount pending)
- Swift typecheck/build: NOT_RUN
- Apple API availability, AVAudioRecorder permissions, device recording/playback, accessibility visual QA: NOT_RUN
- Network/provider/media/OSS/recording/permission actions: NOT_RUN, deliberately no live actions
- Shared-main edits and remote changes: none
- Parser: PASS, 8 Swift files, 0 recovery nodes/diagnostics using pinned Tree-sitter; supplementary parse only, not typecheck/runtime evidence

Coverage includes exact JSON/multipart shapes, business failures, top-level ASR, safeText fallback, missing code, voice size/duration, default-off grants, review/cancel non-dispatch, confirmation binding, voice-format gate, unknown outcome UUID preservation, local/HTTP rate gates, identity reset, in-flight duplicate tap, late response discard after exit/access revocation, and failed regeneration preserving answer identity. UI cases cover disabled mode, review-before-send, disabled voice, and background invalidation.

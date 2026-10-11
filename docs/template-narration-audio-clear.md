# P036: Clear narration audio

## Source mapping and implemented scope

The sole master construction document identifies `clearAudio` under P036, the existing professional template publisher. Its Mini program implementation clears `audioUrl` and `audioDuration` together after destroying the active audio preview. The corresponding native voice module previously offered only separate reference and duration fields.

This slice adds an explicit **Clear narration audio / 清除导览音频** button beside those fields. It clears both native fields in one local draft replacement, retains the enabled voice module and all unrelated fields, and invalidates a pending local media inspection before mutation. The empty enabled voice module remains subject to the existing publication validation. No backend requests or publishing permissions are added.

The native draft has no `audioFileName` or `audioFormat` properties, so this slice does not invent them. The existing native media review is inspection-only. Remote audio playback and upload remain outside this slice; clearing a reference does not delete the remote file.

## Local lifecycle

- Capture the visible audio reference as exact UTF-8 bytes and its optional duration.
- Clear nil/empty/whitespace/opaque historical references and orphaned durations without parsing or normalizing them.
- Reject callbacks after a changed reference/duration, committed draft edit, reload, restore, discard, review preparation, dismissal, owner/session change or write lock.
- Use the current draft as the output base, preserving unrelated fields.
- Repeated activation is a no-op after the first clear.
- Synchronously invalidate inspection before either field changes. A late inspection completion cannot restore the cleared reference.
- Existing draft persistence is used. No automatic clearing occurs when opening or leaving the form.

## Integration

Apply after the pending product union based on `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`. The before image of `App/TemplateAuthoringDetailForms.swift` is that union's after image, including story image removal. The new change is limited to the voice section; the story section is preserved byte-for-byte.

Merge `docs/localization/template-narration-audio-clear.json` additively into the central catalog. Use `docs/registration/template-narration-audio-clear.json` to register the two new app sources and app-hosted test file in the normal project integration step. The worker does not edit the central PBX, catalog, generator or CI.

## Verification

- Focused Python contracts check the UI route, lease checks, atomic paired-field removal shape, media invalidation ordering, preserved image removal, localization and registration fragments. These are source checks only.
- Six pure Swift tests cover paired clearing, opaque/empty/orphaned data, disabled state, changed target, Unicode byte identity and unrelated-field preservation.
- Ten app-hosted tests cover idempotence, fresh-coordinator local restore, dismissal, immediate target changes, committed ABA edits, module toggling, reload/restore/discard, review cancellation, owner/sign-out, late inspection completion and durable locks.
- Swift execution and device/UI acceptance require an Apple toolchain. An authored test is not a passing test; see delivery evidence for the exact executed status.

Suggested Apple checks after registration: `swift test --filter TemplateNarrationAudioRemovalTests` and the `TemplateNarrationAudioClearTests` app-unit class. Manually verify Chinese/English labels, VoiceOver, duration-only data, repeated taps and re-entry.

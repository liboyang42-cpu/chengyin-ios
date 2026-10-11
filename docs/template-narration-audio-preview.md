# P036: Read-only narration preview

## Source and scope

The master P036 event index includes onPreviewAudio. The Mini implementation selects the current narration reference on a user tap, toggles a retained player between play and pause, and invalidates the player instance and generation on source replacement, clearing and unload. Old callbacks cannot revive a replaced source.

This native slice adds the preview entry directly to the existing template voice module, following the separate clearAudio candidate. It reuses PlatformAudioPlayback and PlatformAudioConsumerView. It does not construct another audio engine, upload media or change a draft. The Mini behavior that backfills audioDuration is intentionally excluded: the requested native preview is read-only.

## Playback and trust boundary

Selecting the entry does not play or fetch audio. It mounts the existing player UI. The existing explicit URL-origin review remains required before playback. Subsequent taps pause/resume only an already-consented playing/paused instance. A loading, failed, interrupted or ended presentation is handled by the existing consumer UI.

The existing projectChapterAudioPlayback environment is the app's already-wired session-owned audio factory. It remains optional and nil in production defaults. No new factory, origin allowlist or backend capability is introduced. An injected player can leave its gated state only when its existing policy approves the exact HTTPS origin. Invalid/whitespace/credential-bearing/fragment/file/http references are unavailable; historical values remain untouched in the editable text field.

The reused native driver bounds downloads, checks redirects against the same origin policy, avoids cookies/credentials/cache and disposes the playback session. Those components are unchanged here and their Apple/runtime acceptance is not established by this slice.

## Lifecycle

- A capture binds controller generation, model/media generations, session, draft identity and exact UTF-8 reference bytes.
- The controller subscribes to the editor's synchronous objectWillChange publisher, retiring its player before draft replacement. Clearing, direct source changes, same-value reloads and ABA edits cannot keep an old player alive.
- Other draft edits conservatively stop preview too. This avoids playing narration against a changed authoring context.
- Navigation, module removal and background/inactive scene transitions dispose the player and retire the capture. Re-entry requires a new selection and review.
- The existing session owner invalidates player instances on account/token transitions. Local capture checks and synchronization independently reject stale owner/context callbacks.
- Old close/open callbacks cannot affect a newer selection. PlatformAudioPlayback's existing generation checks reject late native driver events.
- No draft field, especially audioDuration, is automatically updated.

## Integration and verification

Apply after the exact clearAudio candidate. The single UI after image adds one preview-entry line and preserves the clear action and prior story image deletion. Merge the localization fragment additively and register the single new app source and its app-unit test through the normal integration workflow. Central PBX, catalog and CI are untouched.

Five focused Python checks cover routing, reuse, trust gates, read-only source shape, lifecycle wiring and fragments. Eleven authored app-unit tests exercise explicit consent, disabled/unknown-origin gates, invalid URLs, repeated pause/resume, pending-download clear/source replacement, ABA edits, reload/restore/discard/leave, module removal, background-style deactivation/re-entry, owner change and late failure/end/interruption events.

These source checks do not compile Swift or play audio. The current authorized machine lacks Swift/Xcode, so app-unit execution and Apple/device UI acceptance remain NOT_RUN. The ordinary production screen remains honestly unavailable until an independently approved session audio factory is supplied. This delivery must not be reported as live audio readiness or complete P036 parity.

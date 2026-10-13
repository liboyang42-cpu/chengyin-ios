# Normal legacy-question preview entry

P036 `onPvAnswer`, `onPvSelectChoice`, `pvUseHint` and `pvSubmitChallenge` form one local text/choice challenge loop in the normal preview. The existing native `TemplateLegacyQuestionRehearsalView` already implements that full loop, but its only entry was the completion-configuration page. The normal preview summary showed the question/options without an attempt entry.

The normal summary now offers that existing page when the unchanged `TemplateLegacyQuestionRehearsal` projection says legacy text/choice is available. Opening additionally requires a configured question, an editable current owner snapshot, and an empty current route. An advanced primary game, disabled completion, malformed/incomplete answer, hidden preview, changed owner or stale callback cannot open it.

The repaired66 sheet owner, immutable snapshot, unique destination identity and both navigation binding fences are reused. The original legacy Core/App bytes and their local answer, selection, hint and submission rules are unchanged. The new route has no persistence, grant, upload, audio playback or player/reward-service action. Existing localization keys and registered Swift/test files are reused; there is no PBX or catalog delta.

Four new App tests cover actual local text/choice attempts with zero parent model publication, unavailable cases, stale route/read/pop callbacks, and a UIHostingController normal-summary navigation round trip. All eighteen preceding native methods remain byte-identical. Native tests are NOT_RUN here. Source checks, six exact Mini-method scenarios, Swift grammar and positive/reverse tree evidence are supplied separately; none is a native compilation or runtime pass.

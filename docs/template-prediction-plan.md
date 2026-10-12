# Prediction plan editor (P036)

## User flow
Open Creator → prediction → enable → Prediction plan. Edit question and instructions, add a choice with an automatically allocated key, type its label, and remove any targeted row. Keys are reference-only. The existing native schema permits 2–4 choices; deletion permits an empty intermediate list with visible validation so it can be rebuilt. Add stops at four. Imported duplicate keys remain visible by occurrence and can be removed rather than silently renamed.

Choose cutoff hour (0–23), relative reveal day (0–30), and reveal hour (0–23). Day labels use same/next/two days and the numeric offset. A summary shows these same values without manufacturing calendar dates or time zones. Same-day reveal before cutoff shows the existing validator's conflict and can be repaired with any of the three pickers; equality is allowed. No automatic rescheduling. Save invokes the existing local draft action. XP and the existing read-only local rehearsal stay in the parent form.

## Exact requirement evidence
Sole MASTER-v10-extracted-text.txt P036 lines1616–1619 lists onAdvancedField/onAdvancedPicker/addAdvancedRow/updateAdvancedRow/removeAdvancedRow. Real temp-index.js92–109 directly defines rowId, ADVANCED_ROW_TEMPLATES['predict.options'], PREDICT_HOURS, PREDICT_DAYS and labels. JS507–513,565–611 implement scalar/picker and row changes. WXML488–506 exposes the complete prediction form with label-only options and all three pickers. No generated examples substitute for source.

Opening reads current draft values without rewriting. Source uses timestamp/random opt_ keys; native continues its already-supported unique opaque options_N allocator. The actual Mini permits unlimited appended rows; native retains the existing schema's maximum4. Defaults for missing time fields are the existing native20/1/20 defaults, not inferred from source. Numeric strings remain intact until the user picks a number. Unsupported shapes stay in the original generic editor; future row/section keys and unrelated families/XP survive edits. No migration or new publish permission.

## Scope and invalidation
Each controller is scoped to owner/session/identity, media epoch and exact UTF-8 JSON fingerprint of prediction. Continuous own text entry stays live; structural edits retire old row inputs and actions so removed indices cannot be retargeted. External draft ABA, lock, owner change, restore/load/discard, leave/background retire the editor. Reload reads the current draft. Mutation uses model.changed(); save uses model.save(). No new transport, storage, authorization, outcome settlement, reward, sensor, upload, reminder or notification behavior.

## Integration
Base5dd3e53c1de104735b26d75811cb4ff46b2a340f includes published creator5–15 and root hotspot/PictureChoices fixes. No dependency on sealed16–20. Common file is an incremental three-hunk merge, never a replacement with this isolated after image. Registration and17 English/Chinese localization strings are fragments only; central PBX/catalog remain unchanged. The optional cumulative16/17/19 compatibility check is recorded with its input SHA.

## Verification limits
13 Core and13 App XCTest cases are authored. Native Swift/Apple tools are absent: compile, XCTest, simulator/device, SwiftUI picker interaction, accessibility and actual disk restore remain NOT_RUN. Python checks inspect relevant source contracts. Node executes the original Mini pure helpers/handlers against an isolated form-state stub; it is not a native or production run. No server, rewards, player outcome or notifications are exercised.

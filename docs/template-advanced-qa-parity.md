# Existing mini-program QA publishing parity

This is a narrow compatibility repair to the existing native template publishing flow. It adds no publisher, schema, endpoint, permission or activation.

## Source evidence

The mini-program source at `5f1df61e42b89e7acb1de21ce95557d9bde5d73e` already implements this behavior:

- [Selected gameplay bypasses duplicate legacy-field validation](https://github.com/liboyang42-cpu/chengyin/blob/5f1df61e42b89e7acb1de21ce95557d9bde5d73e/chengyinhub-xcx/pages/publish/temp/index.js#L2624-L2638): the selected advanced game is validated through its configuration; only legacy templates require the old question/answer fields.
- [Existing game catalog](https://github.com/liboyang42-cpu/chengyin/blob/5f1df61e42b89e7acb1de21ce95557d9bde5d73e/chengyinhub-xcx/pages/publish/utils/publish/node-game-catalog.js#L22-L24) maps QA `TYPE` to verification method 1, `PICK` to 3, and `SHOT` to 2.
- [Existing template draft/publish routes](https://github.com/liboyang42-cpu/chengyin/blob/5f1df61e42b89e7acb1de21ce95557d9bde5d73e/chengyinhub-xcx/pages/publish/temp/index.js#L2716-L2745) remain the reference; this change does not replace them.

Native base `a7aa188db0476b36ff1e4de980dcfeb9a122d9a5` already has the QA configuration UI, `TemplateAdvancedDraft` validators and `TemplateAuthoringContract` serialization. Its `TemplateAuthoringDraft.publishIssues` additionally required legacy text/choice fields even for a valid advanced QA configuration. That could block a correctly configured existing QA draft from reaching publish review.

## Repair boundary

Only enabled `qa` with `TYPE` + `.text`, or `PICK` + `.choice`, skips the duplicate legacy answer requirements. Existing `advanced.issues` still validates the QA question, answer/options, schema, media and other enabled configuration. Disabled QA, mismatched verification modes and unrelated modifiers do not receive this bypass. This does not attempt to port the entire mini-program game selection catalog.

`TemplateAuthoringContract`, request paths/methods, wire fields, media serialization, coordinator, permissions, held native text-draft work and admin authoring are unchanged. Existing unknown-field/unsupported-version rejection remains in the advanced validator.

## Verification boundary

Five XCTest methods cover valid TYPE/PICK without legacy answers; disabled/mismatched cases; invalid advanced answers/modes; unrelated modifiers and valid legacy fallback; and exact existing draft/publish request plus media preservation. They are authored tests and need the normal Swift/Apple gate. Linux has no Swift compiler, so they have not executed here.

Existing Python source-contract checks executed: 56 template checks (45 pass, 11 unavailable-source skips) and 47 creator checks (46 pass, 1 unavailable-source skip), zero failures. These checks are not Swift runtime acceptance. No live publishing or credential activation was performed.

# Employee-role permission explanations

## Ordinary-flow gap and implementation

The existing employee invitation and change-role form already loads the server's role list. Its permission section previously printed raw codes only. The mini-program's existing team role sheet supplies readable scope descriptions, so this change brings that readability into the same native form without adding a module or activating writes.

`MerchantOperatorRolePresentation` maps the selected record's exact permission strings to bilingual descriptions. It never derives permissions from a role name or assumed preset. `MerchantOperatorRolePermissionSection` displays each supplied permission's title and explanation; the complete raw list remains available in a disclosure. Unknown codes are shown verbatim beside an explicit unknown explanation. Empty lists state that the server supplied no permissions. Empty unknown codes and unavailable projections have explicit states.

Duplicate codes are collapsed only in the display, preserving source order. Whitespace, case variants and wildcards are never normalized into recognized permissions. There is no persistence or cached permission list. Changing the selected role updates the projection directly.

The form retains its server-provided role names and exact selection IDs. The existing local review, frozen confirmation, fresh authorization checks, owner/session fences and unknown-result journal are unchanged. No permission is granted or revoked by this presentation layer. No new read request, permission prompt, communication, financial action or production capability is enabled.

## Source evidence

Pinned source: `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`.

- [Mini team page](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/merchant/team/index.js): `loadRoles`, `rolePermissionText` and existing invite/change-role selection. Blob `46ad9d5a9c90a87c24e634317a17cbbf7e6dd730`.
- [Mini role sheet](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/merchant/team/index.wxml): selected-role options display readable permission scope. Blob `98f720912868aa6333f19fdfc452f5f13cc8d4d4`.
- [Exact backend permission codes](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-system/src/main/java/com/chengyinhub/business/access/merchant/MerchantPermission.java): 20 recognized codes. Blob `30c3b57ae6ff6bd780fbdc8098898988f153b745`.
- [Backend role policy](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-system/src/main/java/com/chengyinhub/business/access/merchant/MerchantPermissionPolicy.java): role grants remain server-owned and are not copied into the new projection. Blob `aec63e4378cde61cac8d42cd04060dac1296909f`.

The mini page's short category summary is not treated as a complete authority for individual grants. Native explanations preserve distinctions between verification execution and record reading, ordinary and sensitive customer reads, marketing read/write, and aftercare read/response/opinion/evidence. Aftercare opinion and financial read descriptions explicitly do not promise a refund or payment.

## Integration

Apply the candidate patch against frozen native tree `e562555019d9719c3abafe0d77741c7b43a750f0`. Merge all 47 entries from `Resources/MerchantOperatorRoleLocalizations.fragment.json` into the existing string catalog; preserve unrelated entries. The fragment is additive. Regenerate the Xcode project with `python3 tools/generate_project.py` so the new Core and App files are included. Package.swift automatically discovers the Core test file.

The only existing source-file change is the two-line permission-section replacement in `App/MerchantBusinessEditor.swift`. Home, customer detail, settlement, aftercare, Operations, mutation transport, authorization and journal files are byte-preserved.

## Verification scope

- 10 new Python source contracts cover exact code inventory, existing form integration, unknown and empty presentation, bilingual key coverage, Dynamic Type/accessibility declarations and absence of new authorization/transport/persistence.
- 12 Swift Core tests are authored for exact matches, unknown codes, duplicates, empty lists, misleading role names, role changes, refreshed records, distinct sensitive/read/write codes, non-role and malformed input, and unchanged documents/requests.
- Supplementary Tree-sitter parsing covers the four new or modified Swift files. A parser pass is not typechecking or runtime evidence.
- Swift Core test execution, Apple compilation, Xcode builds, AppUnit/UI tests, VoiceOver, Dynamic Type layout and real backend acceptance are **NOT_RUN** in the Linux executor. No AppUnit or UI execution is claimed.

On Apple infrastructure, exercise both invitation and change-role sheets, switch roles repeatedly, expand codes, cancel and reopen, use English/Chinese and accessibility text sizes, and verify that the frozen confirmation retains the selected server role code. No real staff-permission change is required for those presentation checks.

# C10-ios shared hunk for dot

Exclusive owner: Cursor C10-ios (`cursor/c10-ios-workshop-h5-e504`).
Base: `migration/native-ios` @ `76ce1b313af2595f9b7d7ace49040866209c7974`.
This file is the only shared hunk. Do not treat it as authorization to edit AppSession / AppCompositionRoot / pbxproj / Localizable / existing Core/Workshop* / public author-publish registry / Runtime from the Cursor line.

Coverage is **not 100%**. Missing originals stay WAITING_SOURCE. App / XCTest / CI = **NOT_RUN**.

## Why this hunk exists

Issue 5 C10: 工坊、模组/H5 与作者发布消费闭环。公共作者发布/安装登记/Runtime 不可整文件接管。
New Core types are SwiftPM-visible (`Package.swift` `path: "Core"`). Xcode `check_scaffold.py` still requires every `Core/*.swift` file to be listed in `Questify.xcodeproj/project.pbxproj`. C10 must not edit that project file.

## Inventory (reuse, do not rewrite)

30 existing `Core/Workshop*.swift` files on this base. Grep `rollback|installPackage|qmod|H5Session`: **NO MATCHES**.

| file | what it already covers |
|---|---|
| WorkshopCreatorConsent* | creator consent |
| WorkshopCreatorPending* | pending review of creator terms |
| WorkshopOwned* | owned library + package metadata (`schemaVersion == 1`, contentHash/termsHash) |
| WorkshopPurchased* | purchased library metadata; `permitsContentUse` / `permitsPurchase` are false |
| WorkshopPaidInstall* | paid install of **PRIVATE DRAFT** (`W18_PRIVATE_COMPONENT_ONLY`, `executable=false`) |
| WorkshopPaidInstalledText* | private-draft installed text |
| WorkshopPaidProfessional* | professional materialization of owner draft |

Existing paid install is an independent deployment grant into an owner draft. It is **not** qmod runtime, **not** H5 session, **not** upgrade/rollback, **not** server pass verification.

W18 workshop paid module marketplace is historically DO_NOT_PORT as merchant plugin catalog. Do not revive IAP or WeChat pay for virtual goods. Digital/physical/IAP rules remain OpenDecision, not launched.

Public catalog facts only: answers and hidden coordinates must not ship in packs (same as C05 `OfflinePackOperation.inspect`). Existing `Core/DiscoveryContracts.swift` already bans arbitrary banner H5 (`Never open arbitrary H5 URLs from a banner`).

## WAITING_SOURCE (typed failures, do not guess binary formats)

These originals were not readable in this public tree:

- unpushed iOS SHA `e2d86c4` + 16 dirty (`ios.e2d86c4.unpushed`)
- 232-file impl pack hashes (`implPack.232.hashes`)
- v12 Questify DOCX (`questify.v12.docx`)
- H5 container / SDK / module-pack original texts (`h5.container.original`, `h5.sdk.original`, `module.pack.original`)
- old qmod workshop candidate binaries (`qmod.original`, `qmod.workshop.candidate.binaries`)

If a capability needs those originals, exclusive machines return `waitingSource(capability:)`. Never a fake success path.

## Dot-owned integration (do not apply from this PR)

1. **pbxproj** — from this SHA, run `python3 tools/generate_project.py` so these new sources join the Questify target. Object IDs match `generate_project.py` `ident()`:

| path | PBXFileReference | PBXBuildFile |
|---|---|---|
| Core/WorkshopModuleImportGate.swift | EC2396AB1E58FF31C9DA3D31 | 4CD2E23D36E029820918E398 |
| Core/WorkshopPackageVersionPublish.swift | 9170F55A3C7C4038C70A0A1A | 82F961E3C0A24B4AB19E86BC |
| Core/WorkshopInstallUpgradeRollback.swift | D00B0A732768D6FAEF4EF81B | 975DB2D106D976ECCCFAEC13 |
| Core/WorkshopRunServerVerification.swift | A5982C4643AB55FD6A887484 | 153C479832ED7E0FC147B101 |
| Core/H5SessionCapabilityGate.swift | F1A61B420943ACE3EF23D176 | D0AB5DD2A1B915B5AC63E4E7 |
| Core/H5AnswerProtection.swift | 374ABBA7A1C3A8130ECC5C35 | 8B51CD78770155F19560665F |

CoreTests are SwiftPM-only (`Tests/CoreTests`); they are not Xcode app-unit sources.

2. **Public author-publish / install registry** — not owned here. `WorkshopPackageVersionPublish.registerPublicAuthorPublish()` is a typed `publicRegistryReserved` refusal. When the original registry exists, inject it behind that seam. Do not let C10 own a second studio or second source of truth.

3. **Existing WorkshopPaidInstall*** — stays the private-draft grant. Exclusive `WorkshopInstallUpgradeRollback` is unwired. Do not merge them. Do not set `executable=true` from this line.

4. **AppSession / composition / Runtime** — do not wire C10 into `AppSession`, `AppCompositionRoot`, or RuntimeDependencies from this candidate. Import gate `writeRuntime()` is a typed refusal. JS is never executed.

5. **Localizable.xcstrings** — not edited.

## C10 already landed (do not rewrite)

- Import from a normal entry → validate manifest (`id`, `version`, contentHash sha256 64 hex, `schemaVersion==1`, no answers/hidden coords) → metadata-only preview → review pending
- Unknown module format / missing qmod original → `waitingSource("qmod.original")`
- Version publish freezes exact contentHash+termsHash+versionLabel; same `originalRequestID` republish is idempotent; mutating frozen hash without new version fails
- Authorized hold (not IAP) → install / upgrade / rollback to retained prior; same `originalRequestID` cannot double-install; rollback without prior fails
- Run pass/fail from server receipt bound to `originalRequestID`; JS/H5 self-report rejected; UNKNOWN keeps original intent, does not mint a new requestId, does not treat current projection as success
- H5 session: signed domain allowlist + frozen SDK capability set; missing original spec `waitingSource("h5.sdk.original")`; version incompatibility rejects; arbitrary H5 forbidden
- Answers never in client pack; compare only server-side frozen author version; client clock / JS report cannot succeed

## SHA256

8a48cd52b829d09bfd8cf4be89a10e3c975aabb9bee75f2e489d14044be2e08c Core/WorkshopModuleImportGate.swift
f94cdbdc52ee252f7316d767b3e3d0efb08822762d6a5d2357517af2c51cd73d Core/WorkshopPackageVersionPublish.swift
840e9ae8efa6522987fe74d05258fa2bb18532649aa914d7b3d8babe1d142504 Core/WorkshopInstallUpgradeRollback.swift
208170dca021866e84a10a25e8ea5a824a2f72f8c7b97a0a7eef3c2297d92f1c Core/WorkshopRunServerVerification.swift
95ec8243ec49d28c1dfa1f11c4382d23017f22b3a67b21f61752cb9f30713c62 Core/H5SessionCapabilityGate.swift
06bc3570cc7ee364c2aa16861ba21e46f2ce536bec7b20ac14f0cf5d7ee16064 Core/H5AnswerProtection.swift
c9e430ebd1cc7e9b9bc318cc5426c68f6c258b46d0615b569a2e0db48cd262ec Tests/CoreTests/WorkshopModuleImportGateTests.swift
7e9e6640392711e2e6b3967d03d2a87a717b1f362922a2c9fee7140c72ff4e6b Tests/CoreTests/WorkshopPackageVersionPublishTests.swift
8bd020ccb5e6145c9f6220ab83ff4e83ce57ed4eeaead24bdf1a8e3fc8b0e3df Tests/CoreTests/WorkshopInstallUpgradeRollbackTests.swift
1c736710bd2d10f7e712ed737f1889cf1eda6956d9de376171e118f5577cebde Tests/CoreTests/WorkshopRunServerVerificationTests.swift
b2be7ca1865ec64ad84b904822758784554dc729574c9bb1bae446a6ad39ed04 Tests/CoreTests/H5SessionCapabilityGateTests.swift
d2ca01d34f1b1327e0081dadec2c8e4cd257d7a3e236cef2a86b49857e9166a1 Tests/CoreTests/H5AnswerProtectionTests.swift
47a12ac022ef30b193d7262723e963b76ff461ec3bbe46b0978b7f1564888a9e Tests/ContractChecks/test_c10_workshop_h5.py

## Verification note

Linux: `python3 -m unittest Tests.ContractChecks.test_c10_workshop_h5` from the chengyin-ios worktree cwd (not `/tmp`).
Swift XCTest / App / CI: authored, **NOT_RUN** on Linux. iOS 13.0 baseline is not raised by this line.
No credentials. No real IAP.

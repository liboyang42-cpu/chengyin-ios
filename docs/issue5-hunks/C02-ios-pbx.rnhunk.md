# C02 iOS pbx hunk (dot-owned)

Do not apply from this exclusive line. `Questify.xcodeproj/project.pbxproj` stays with dot.

Base: `migration/native-ios` `76ce1b313af2595f9b7d7ace49040866209c7974`.

`Package.swift` already compiles every `Core/*.swift` leaf and discovers `Tests/CoreTests`. The Xcode app target still lists Core sources explicitly.

## Inventory (reuse, do not take over)

Existing Play/RPG/character surfaces kept as hosts: `App/PlayExperienceView.swift`, `App/PlayAdvancedView.swift`, `App/PlayAdvancedTeamViews.swift`, `App/PlayPlayerTeamStatusView.swift`, `App/PlayObjectCardRevealView.swift`, `App/SessionPlayRuntimeView.swift`, `Core/JourneyCheckCoordinator.swift`, `Core/PlayPlayerTeamReadback.swift`, `Core/PlayAdvancedTeamProjection.swift`, `Core/JourneyRoleProjection`. Merchant NPC character readback is a different domain.

HTTP reused: `PlayExperienceService.request`, `playerProjection`, `playerCommand`, `playerReceipt`. No second writer, dice, wallet, or request ledger.

## Object IDs

| path | PBXFileReference | PBXBuildFile |
|---|---|---|
| Core/WorldEnvironmentProjection.swift | 9A7A1ABBD54A4490BAD39CA1 | 1116D159A2A84FF99E53F093 |
| Core/PartyRosterProjection.swift | 7303562FBC934B8F8085C484 | D82544EFF0A949AAB327D4DA |
| Core/CharacterCardReadback.swift | 3E66D03105B44A40AB14FBF3 | 074DC406DE614CD0BC25509B |
| Core/EnvironmentExpiryClock.swift | 512E9A186AE04EB6BD750F88 | 9C252AB70B154DFCAEFD6D6C |

CoreTests stay on the SPM `QuestifyCoreTests` directory target. Optional `Resources/WorldEnvironment.fragment.json` is not the shared `Localizable.xcstrings`.

## File reference objects (insert near ClubTerminalSessionProjection.swift)

```
		"9A7A1ABBD54A4490BAD39CA1" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/WorldEnvironmentProjection.swift";
			"sourceTree" = "<group>";
		};
		"1116D159A2A84FF99E53F093" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "9A7A1ABBD54A4490BAD39CA1";
		};
		"7303562FBC934B8F8085C484" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/PartyRosterProjection.swift";
			"sourceTree" = "<group>";
		};
		"D82544EFF0A949AAB327D4DA" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "7303562FBC934B8F8085C484";
		};
		"3E66D03105B44A40AB14FBF3" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/CharacterCardReadback.swift";
			"sourceTree" = "<group>";
		};
		"074DC406DE614CD0BC25509B" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "3E66D03105B44A40AB14FBF3";
		};
		"512E9A186AE04EB6BD750F88" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/EnvironmentExpiryClock.swift";
			"sourceTree" = "<group>";
		};
		"9C252AB70B154DFCAEFD6D6C" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "512E9A186AE04EB6BD750F88";
		};
```

## Group children

In group `19F479106CE8C3BA8C106518`, after `"CD67475D43FFD2D955BEC7F5"` add:

```
				"9A7A1ABBD54A4490BAD39CA1",
				"7303562FBC934B8F8085C484",
				"3E66D03105B44A40AB14FBF3",
				"512E9A186AE04EB6BD750F88",
```

## Sources build phase

In `878A52FC5FF6A57D50B7B870` PBXSourcesBuildPhase, after `"9BF7536550C8D523C539CF39"` add:

```
				"1116D159A2A84FF99E53F093",
				"D82544EFF0A949AAB327D4DA",
				"074DC406DE614CD0BC25509B",
				"9C252AB70B154DFCAEFD6D6C",
```

## SHA256

5f8416501af443af8f2acffc36d7e1c8e35868f2e21d382db9a755e1f007f2d0 Core/WorldEnvironmentProjection.swift
4c3c01dc14df64a7824e0c307353ebab688b221af1ea4c9c1a748734eda09380 Core/PartyRosterProjection.swift
258fcbcf62c7bafc8410ee27696e846e196794af766551801fc62f25a06c4c2a Core/CharacterCardReadback.swift
63442a497cd416a53032e2cf46c544dddb1ef2ad1844113f9271ccf95704a17d Core/EnvironmentExpiryClock.swift
c051ee13c51b303ea6b6f961811db6ebb04cab054d0dede7e74401296c8d0841 Tests/CoreTests/WorldEnvironmentProjectionTests.swift
28cc42a977cc43bda072cfe7613bd8bb6d3bfa83214aed4f501e7f8888c4417b Tests/CoreTests/PartyRosterProjectionTests.swift
a0bb762d253e89220ce2c34765f9826bd6afed902d51f3250b98207c5130a766 Tests/CoreTests/CharacterCardReadbackTests.swift
25dce9565d87ac3d5e7a2ce579087d1def7fca09f0da1cf79178ad4ecb0139de Resources/WorldEnvironment.fragment.json

## Blockers

- Linux XCTest NOT_RUN. Contract checks: `python3 -m unittest Tests.ContractChecks.test_c02_world_party_character`.
- Xcode compile / simulator journey blocked until dot applies this pbx hunk.
- Dedicated RPG party/equipment expiry fields are WAITING_SOURCE unless the signed character, rpg/status, or session-view payload includes them. No client weather and no device-clock success.
- Runtime wiring (`AppSession`, composition root, routes) remains with dot.

# PlayKit games polish (2026-11-21)

Owner request: every game smooth, consistent with the story, and natural. This pass is the iOS side of the mini-program `fix/games-polish-1121` / `fix/games-theme-1121` audit. Server authority, review/confirm sheets, recovery and input contracts are unchanged.

## What changed

- **Story header.** `PlayGameStage` (Core) resolves 「第N站 · 站名」, the chapter and the station's lead line (`hookText`, first line) from the current route read. Hosts set it through the `playGameStage` environment value: the chapter story's inline game, the station page's game list and each game opened from it. `PlayGameStageHeader` draws it synchronously in the chapter-story typography, so it is present on the first frame and does not shift the game. The app has no per-route theme or look yet, so the existing system look and accent are used.
- **One primary button.** Every game's main action uses `playGamePrimaryButton()`: the system prominent button at the large control size. No extra press animation is added.
- **Captions.** System, developer and "the server decides" captions are removed from the game bodies. The only short safety lines kept are the motion/microphone purpose lines and the microphone privacy line ("只听音量，不录音。").
- **Result in story voice.** `PlayGameOutcome` mirrors the earlier result rules exactly and picks story-voice copy: passed, not passed, try again while still open, recorded, and photo-awaiting-result. The branch cast line 「{name}会记住这件事」 is unchanged. The result block fades in with `QuestifyMotion.content` and appears at once under Reduce Motion.
- **Continue only after finishing.** A 「继续故事」 action appears on a game screen only when the server state is terminal, nothing is pending and the phase is ready (`PlayGameOutcome.showsContinue`). The chapter's 「回到路线」 action is hidden while an inline game has unsent input.
- **Per game.**
  - The random deck shows a face-down deck before the first draw.
  - Dice show a resting die before the first roll.
  - A branch with no options yet shows a quiet waiting line.
  - The hidden-object picture keeps a fixed-ratio placeholder while it loads, fails or is waiting for media access.
  - The estimate wheel shows the chosen number with its unit beside it, with proper number formatting.
  - Match draws a line between each current pair in a two-column diagram above the pickers, which remain the accessible way to pair.
  - The hangman and compare fixtures use Chinese sample copy.

## Not on iOS

The mini-program `accusation` and `album` PlayKit components have no iOS PlayKit screen, so there is nothing to polish for them here.

## Verification

- Core: `Tests/CoreTests/PlayGameStageTests.swift` covers station numbering, chapter and lead resolution, the outcome mapping, continue gating, the unit formatting and the match lines.
- Offline: `tools/check_scaffold.py`, `tools/check_native_motion_tokens.py` and the contract checks.
- Swift compilation, simulator UI and device checks run in CI on macOS only.

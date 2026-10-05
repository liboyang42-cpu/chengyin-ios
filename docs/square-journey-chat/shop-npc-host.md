# Shop NPC host preparation

No files in chengyin-ios were edited by this preparation. The isolated validation target is under this directory.

## Apply once after packet copy

python /tmp/shop-npc-host-prep/prepare_host.py --root /workspace/scratch/a192988f79fd/chengyin-ios --write

Without --write the command prints a diff only. All unique-anchor checks and new-file collision checks finish before any writes. The script is intentionally not re-applicable: integrate once, then review later edits normally.

## Files

New:
- Core/PlayNPCBrief.swift
- Core/ShopNPCAuthenticatedTransport.swift
- App/ShopNPCSessionHost.swift
- Tests/CoreTests/ShopNPCHostTests.swift

Anchor-based changes:
- Core/PlayContracts.swift
- Core/ShopNPCCoordinator.swift
- Core/ShopNPCHTTP.swift
- App/ShopNPCView.swift
- App/PlayExperienceView.swift
- App/SessionPlayRuntimeView.swift
- App/AppSession.swift

Existing Journey, ambient, device, stillness, preference, summary, player, circle, prefab, audio and maps arguments are preserved. Public merchant NPC and old read-only PlayNodeDetailView are unchanged. The node conversation is mounted on the normal SessionPlayRuntimeView journey node destination.

## Safety contract

Only a currently loaded, active, unlocked, visible Play node with a nonempty source npc.name can yield a destination. Node ID never derives from merchantId/bizId. Account, current login gate epoch, regional namespace, effective role and monotonically increasing access revision bind the scope. Role is an identity discriminator only, not an authorization grant.

Host grants and production dispatch are immutable OFF. The concrete transport uses the existing central HTTPTransport + raw Authorization convention, rechecks exact current scope/grants before send, validates the text nodeId against scope, and keeps post-dispatch errors/401/authority changes as unknownOutcome. Matching 401 also invokes host session expiry. No media provider, permission workflow or capture factory is installed.

A state-owned destination creates one coordinator after navigation. The observable owner synchronously invalidates live coordinators when identity/token/role/access changes. Snapshot/authority changes bump access revision and clear conversations. Inactive views hide old NPC name/greeting, clear drafts/capture and disable input. Background/exit invalidates; it does not silently resume.

## Validation

- Isolated anchor application: PASS
- Python byte compilation: PASS
- 60 source/host assertions: PASS
- Tree-sitter: 11 Swift files, zero diagnostics, pinned 0.26.0/0.7.3 toolchain
- Ten Swift host tests authored for NPC decoding, default-off dispatch/grants, exact authenticated node request, role/access changes, authority loss, pre-dispatch revalidation, late reply suppression, post-dispatch uncertainty, and matching 401 expiry
- Swift compiler/typecheck/test execution, Apple SDK, simulator/device: NOT_RUN (unavailable)

Run the main repo's project/source generator so the four new files enter the Xcode graph. AppSession property observer changes will require updating any source tests that assert the old exact willSet string; preserve their semantic media-invalidation assertion. Use the current source parser and complete main test suite after all integrations, not only this isolated check.

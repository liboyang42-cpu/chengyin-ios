# L11 original-install recovery continuation

Owner: existing delegated L11 worker, continuing issue #137. Checked 2026-11-04:
issue comments empty; integration still `eec839502b11f1119a6ede212c768bb3f2de4f29`;
prior L11 work is on `codex/l11-package-safety` at
`7d625c38e50d650251f51eb4bf16c60fd872c8f5`. No new competing workshop/install
branch was found; historical C10 source is reused. Public install registry,
Runtime and shared composition remain outside this work.

Exact continuation whitelist:

- `Core/WorkshopPaidInstallController.swift`
- `Core/WorkshopPaidInstallService.swift`
- `Tests/CoreTests/WorkshopPaidInstallTests.swift`
- `docs/launch/l11-install-recovery.md`

Scope: existing paid **private-draft** installation → durable original request →
status/restart recovery → current-service rejection → presentation retirement.
This is not qmod upload, executable publication, a server H5 result, or IAP.
No new endpoint, writer, permission, credential, storage format or dependency.
The service also preserves its existing typed unauthorized/disabled rejection
after dispatch, so the controller can retire the rejected presentation; it still
keeps a possibly committed mutation's durable original request for status lookup.
The existing current-session invalidation behavior used by initial load/paging
must also apply to current submit and explicit status failures. Retiring a page
must keep the original pending record available to its owner after revalidation.

Baseline reproduction, implementation, actual test results, final hashes and
remote byte receipt are recorded below when available. The frozen backend
contract remains `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`; absent workshop
routes prevent claiming a real server/database/App journey.


## Concrete change and reproduction

On the previous branch head, initial-load and pagination failures retired the
presentation for existing unauthorized/disabled/stale-session results, while
explicit original-status and submit failures returned it to ready. Cached
protected receipt references and newly offered read actions could remain usable.
The submit service also converted a current 401 into outcomeUnknown after its
existing unauthorized callback, obscuring the rejection if the host callback had
not synchronously replaced the current session.

The continuation applies the existing presentation-retirement rule to those two
paths and preserves the service's existing typed rejections. The durable pending
record is never acknowledged/deleted on denial. A later revalidated controller
reads the same original request before history/targets and can recover its real
receipt without repeating submit. Delayed callbacks from a closed/backgrounded or
replaced presentation still fail the original action/lifetime checks.
No server authorization, JWT/RBAC, approval issuance, request body, route,
installation semantics, payment or reward rule changed.

Input blobs at branch parent 7d625c3:

- Controller: `6978df06066764962e386d918795d38fd5c913d4`
- Service: `a101f3a33ccf68445cacbb96dfbe1dd90196d493`
- Existing tests: `c2813905b9724f97e0e48f7a862036d992cd2a37`

## Actual verification

- RED: new current-status/current-submit rejection tests against unchanged
  production methods failed; the 51-test suite recorded 25 assertion failures
  in four new cases. Original tests passed. A fifth dispatched-503 case was then
  added to cover service rejection preservation after a possibly committed write.
- GREEN: the final **52 WorkshopPaidInstallTests passed, 0 failures** in an isolated
  Swift 6.2.1 Debian 13 harness. This includes original success, duplicate confirm,
  storage failure, unknown commit, restart, no-new-UUID recovery, account/role/token
  replacement, grant revocation, late 401, Back/background/resume, pagination and
  protected-body-reference cases, plus the five new rejection journeys.
- `python3 -m unittest discover -s Tests/ContractChecks -p
  test_workshop_paid_install.py -v`: **17 passed**, source/fixture checks.
- Isolated `swiftc -typecheck -parse-as-library -swift-version 5` with the final
  production controller's original Observation macro, final service/contracts and
  production dependency declarations: exit 0. No production macro was removed.
- `git diff --check` and changed-file credential-pattern scan passed.

The Linux executable harness compiles the full production service, contracts,
pending store, wire parsing, API builder and local state logic. It uses the
existing synthetic HTTP transport from WorkshopPaidInstallTests; no real HTTP
request is sent. Unrelated context/session/storage/protected-reference dependency
**declarations are extracted verbatim** from their production files, not replaced
by mocks. The temporary controller copy removes only import Observation and
@Observable because the original Linux executable failed linking
libswiftObservation (`swift::threading::fatal` missing). The original macro was
separately typechecked. The temporary test copy imports FoundationNetworking and
marks synchronous MainActor tests async for Linux XCTest discovery. These edits
are harness-only and are not committed to the app. Existing test-data helper is
copied from WorkshopPurchasedContractsTests; no test expectations are removed.

Commands for the temporary harness:

```sh
swift test --package-path /tmp/l11-install-tests \
  --scratch-path /tmp/l11-install-tests/green-build \
  --cache-path /tmp/l11-install-tests/cache \
  --config-path /tmp/l11-install-tests/config \
  --security-path /tmp/l11-install-tests/security -j 4
python3 -m unittest discover -s Tests/ContractChecks -p test_workshop_paid_install.py -v
```

Module caches were explicitly under /tmp; no credential or home-directory
configuration changed. The same downloaded official Swift 6.2.1 toolchain as the
prior batch was used; its detached signature was not verified because the public
key fetch returned 403, as already recorded in l11-verification.md.

NOT_RUN: full repository package/Xcode build, macOS/iOS XCTest, Observation UI
notifications, SwiftUI/simulator/device, real backend HTTP, actual device storage,
MySQL/Redis, real author upload/review or merchant/player qmod/H5 flow, CI,
production actions. There is still no server workshop route at frozen hengyin
58f4cc4, no qmod compiler/venue/installation adapter into the original publication
and Run writer, and no H5 server ticket/session/result verifier. Thus this is a
complete **client original-install rejection/recovery subgroup**, not L11 launch
acceptance. TECHNICAL_READY=false; PUBLIC_RELEASE_ALLOWED=false.

## Delivery, recovery and cleanup

This continuation changes only the four whitelist files, on the same independent
public L11 branch. No shared file diff is needed, no PR/comment is created, and no
CI is triggered. The branch lies outside push workflow filters; the commit also
uses [skip ci]. The final delivery response records the exact commit SHA and
confirms all four remote files were fetched and compared byte-for-byte.

Before this group, all nine previously uploaded L11 working files were compared
with remote 7d625c3 and deleted locally, along with three completed temporary
source/test trees. The Git index skip-worktree flag records intentional local
absence; these are not repository deletions. New uploaded files are likewise
removed from the local working tree only after the final byte check; temporary
source/test copies are then removed. No unsubmitted or third-party file is
selected for deletion. Everything delivered is recoverable from GitHub.

Final production/test bytes:

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `Core/WorkshopPaidInstallController.swift` | 19967 | `55dd336b95165b4f74d3cc8208d1421726e72630f237fba6a416a5c1e3f9a16e` |
| `Core/WorkshopPaidInstallService.swift` | 14558 | `03f172651f4e37272e61f037cb53bf2d3d213c58943343a1a01c156fc526469e` |
| `Tests/CoreTests/WorkshopPaidInstallTests.swift` | 50893 | `6766b72546b66c6436fc965f79f344fa65249a6c074b396548930bf449185810` |

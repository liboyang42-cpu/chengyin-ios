# L2 environment build inputs

Scope: issue #128, launch-plan baseline `eec839502b11f1119a6ede212c768bb3f2de4f29`.
This is configuration preparation, not a connected login journey or release approval.

## What is implemented

- China and United States profiles each read a market-specific local configuration after clearing the generic endpoint and session realm. A CN endpoint or realm cannot silently become the US profile's input.
- Each market has Development, Staging and Production input files. They reset preceding environment inputs, then read only their matching local override file. Market/environment labels are fixed after the optional include.
- Development's proposed test address is loopback `http://127.0.0.1:8099`; its realm is market-specific. Staging and Production have no endpoint or realm default.
- Local input files are ignored by Git. No real address, credential, developer identity or capability is provided.
- `QuestifyDeploymentEnvironment` is informational bundle metadata. It is not an authorization source.

## Local inputs

Common signing and bundle metadata may remain in `Config/Local.xcconfig`.
Use these optional files for deployment address and realm:

| Profile | Local-only override |
|---|---|
| China | `Config/Local.China.xcconfig` |
| United States | `Config/Local.UnitedStates.xcconfig` |
| China.Development | `Config/Local.China.Development.xcconfig` |
| China.Staging | `Config/Local.China.Staging.xcconfig` |
| China.Production | `Config/Local.China.Production.xcconfig` |
| UnitedStates.Development | `Config/Local.UnitedStates.Development.xcconfig` |
| UnitedStates.Staging | `Config/Local.UnitedStates.Staging.xcconfig` |
| UnitedStates.Production | `Config/Local.UnitedStates.Production.xcconfig` |

Only the relevant non-secret assignments belong in each file. The existing example shows xcconfig's escaped HTTPS scheme form. Do not put passwords, tokens, provider secrets, certificates or production data in any build input. Do not publish actual local files.

## L1 integration dependency

At this baseline, the Xcode project references Base.xcconfig, not China/UnitedStates or the new environment profiles. L1 must choose the intended application-target configurations and integrate the profiles in the shared Xcode project. Do not apply the whole profile as an indiscriminate global test/vendor override. No PBX, scheme or workflow changes are included here.

The generic Base configuration intentionally remains unconfigured. Merely adding or selecting an environment profile does not permit a request or a login. Changing an installed environment's session realm is a migration decision, not automatic movement of existing sessions.

## Owner decision required before connection/authentication changes

No change is made to `RegionalLaunchConfiguration`'s reviewed deployment, its empty verified capabilities, the runtime route/operation approvals, the HTTPS-only API configuration, or ATS.

Therefore the proposed HTTP loopback input is currently rejected by the unchanged HTTPS/deployment gates. L2 must obtain an explicit decision for a narrowly scoped test transport/deployment design before connecting. Do not weaken TLS/ATS globally or enable production grants to make this work.

Capability design, SMS/WeChat/Apple admission, token renewal, sign-out semantics and account deletion remain separate owner-approved work. No refresh endpoint is invented, no provider code is imported from private repositories, and no password path is silently enabled or removed in this slice.

## Evidence and status

Run offline: `python3 -B tools/check_l2_environment_configs.py -v`.
The checker uses an explicit list of tracked inputs and in-memory test overrides; it never reads actual Local*.xcconfig files or contacts a server.

Fifteen test methods cover include ordering, market/environment isolation, blank staging/production defaults, loopback-only development input, ignored local files, metadata and unchanged transport/capability gates.

Xcode build, Swift tests, real test-backend login, guest writes, home/profile/orders reads, token lifecycle and account deletion have NOT_RUN status for this slice. This document does not claim the launch definition of done.

## Rechecked on the complete integration base

All six existing edited file blobs match the fixed integration base above. The prior configuration candidate was retained and revalidated, not taken from private repository history. A new regression reproduced a stale environment label leaking through a market-only local include; market-only profiles now explicitly report `unconfigured` after local inputs. Environment profiles still stamp their own identity afterward.

Additional offline tests cover cross-market and cross-environment override exclusion, clearing invalid inputs and replacing them on a later evaluation, bundle-key mapping to the existing `RegionalLaunchConfiguration.BuildMetadata` consumers, required/optional includes, include cycles, and variable cycles. These tests model xcconfig assignments and includes; they do not substitute for Xcode evaluation. The checker never prints or loads real local overrides.

Actual results: 15 tests before the label fix, 1 failed; the same 15 after the fix passed. No runtime authorization, transport policy or consumer source was modified. Only Config inputs, ignore rules, this document and the checker are in the delivery. Source-only delivery does not satisfy L2's real-backend journey definition.

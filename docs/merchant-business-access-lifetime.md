# Merchant workspace access lifetime (R1)

Scope: the existing merchant business Home access read and its three existing destination kinds. This closes a stale access presentation gap in the W06/W07/W17 merchant workspace; it adds no refund, redemption, reward issuance, endpoint or business authority. The existing `MerchantBusinessReading.access()` / `api/merchant/access/me` service and downstream fresh authorization checks are unchanged.

## Read ownership

- Each visible Home appearance has a one-use token. Leaving retires it and cancels/clears its read, access, loading and error state. A stale disappearance can retire only its own token, not a newer owner.
- Reader identity, scope, authorization generation and configuration are captured together. Rendered access/error/loading are hidden immediately when the live context differs. Retaining the reader prevents object-identifier reuse.
- Appearance entry and current refresh events synchronously admit a unique request ticket. A button or pull refresh cannot activate a retired appearance. Refresh clears previous permissions before starting a replacement read, including replacement failures or missing grants.
- A single SwiftUI `.task(id:)` consumes the captured ticket. The first executable guard in the asynchronous `load` rejects an already-cancelled caller before every shared-state mutation. It then requires the exact ticket, live appearance, reader and context, and rejects duplicate consumption.
- Owned transport work is cancelled on replacement or caller cancellation. Late successes, errors and cleanup all use the same ticket/reader/appearance fence. They cannot clear or overwrite replacement access/loading/error.
- A current request completing after context drift clears only its read and result. It does not retire the visible appearance before Home receives `onChange`; that event must remain able to install a new appearance/ticket. True view departure separately retires the token. Old context callbacks cannot revive a retired token even after a context ABA transition.

## Navigation lifetime

The access-dependent rows remain filtered by the original permissions. Their values point to a stable typed `navigationDestination` on Home's List ancestor, outside those conditional rows. Pushing a child can therefore clear Home access without removing the destination host.

Routes retain the original reader and journal, and bind reader identity, scope, authorization generation and configuration. A destination is resolved only while both dependencies and that current context still match. An old route never obtains a replacement reader or tenant. The original query page, native verification/fallback scan and city-node redemption destinations remain the only three target kinds. They retain their own fresh permission and dispatch checks. Entry visibility is not mutation authority.

## Review correction and evidence limits

The frozen initial `d12fb3ccf46ba2759adf30f8bb25a2117f99553f` candidate is superseded for this work and preserved unchanged. Independent review found that its cancelled late caller could clear a newer owner, its unowned refresh task could restart after departure, and its conditional destination owner could disappear on push. R1 replaces those mechanisms rather than weakening their checks. The initial test asserting that an already-cancelled caller clears cache was incorrect and is removed.

Python source contracts check the exact five-path boundary, full Home inverse to baseline, lifetime guard ordering, request admission, stable route placement and original permissions/destinations. App-hosted XCTest source covers actual model continuations and queued/cancelled ordering; authoring those methods is not execution evidence. This workspace has no Swift/Xcode, strict Swift parser or fresh secret scanner available. Swift compilation, XCTest, simulator/navigation behavior, device behavior and the full matrix remain NOT_RUN. The root integrator owns deterministic registration of the new App and AppUnit files; this owner patch does not edit PBX or project generators.

# P044 customer keyword debounce: bounded candidate

Source baseline: published 6ae3e545b373dd5cddc47356a57d0cb6ee928e70,
tree dc1573c54487cb5402b083b0ff91d3a98025eca9.
MASTER-v10 P044 explicitly lists onKeywordInput and onKeywordConfirm among its
seven events. The real Mini customers page schedules input after 300 ms and
cancels its timer on explicit search. The native baseline only searches on
submit/button, so input alone has no equivalent behavior.

This candidate modifies only the existing App/ClubGovernanceViews.swift
production file. A main-actor timer coalesces keyword edits, retains exact
filter/keyword strings, and releases its pending handle before invoking the
existing authorized load. This avoids a load cancelling its own task.

A keyword change immediately retires the old response generation and clears
its snapshot. Before requesting, the scheduled action checks current operation,
read context, identity, access identity, filter, keyword and task cancellation.
The existing load still owns service authorization and result admission.
Explicit submit/button/filter, refresh, read-context or identity invalidation,
and disappearance cancel a pending keyword timer. UI scheduling helpers are
explicitly main-actor isolated; non-customer branch bodies and payloads are
preserved. No endpoint, directory permission, write, detail editor, central
admission contract, or localization resource changes.

The real Mini was executed in an offline VM for five timer/payload scenarios.
That also revealed two Mini limitations: filter changes leave a keyword timer
pending (two requests), and unload does not cancel it (one late request). Native
cancellation intentionally closes those edges instead of copying them.

Validation claims are separate:
- Python tests inspect exact source wiring, inverse restoration and mutations.
- The Mini VM executes the real JavaScript page, with fake timers and no network.
- Six Swift XCTest methods are authored against the production scheduler with
  injected delays, including cancellation-insensitive sleepers and self-cancel
  prevention. They have NOT_RUN: no Swift/Apple toolchain is available.
- New AppUnitTests target registration and central source/support registration
  are pending a separately authorized integration. This candidate does not edit
  PBX or the previously frozen eleven-file permission package.
- Native view timing, identity-switch UI, accessibility/device behavior and
  full aggregate CI are NOT_RUN. Source checks are not a substitute.

This four-path patch must be integrated against the current remote without
replacing later native diagnostics or other published work. No push, production
request, permission change, or DDL is part of this local candidate.

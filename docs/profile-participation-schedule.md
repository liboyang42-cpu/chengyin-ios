# 本地时间提示完成，生产参与读取仍阻塞

## Approved local increment

MASTER-v10 P116/P117 and the actual `subpackageMember/components/scene-member-participation-detail` Mini component at f859cd6e2618f618a53f5cd33949259828e86313 provide the requirement: prepareDisplayData uses owner schedule, calculateTimeStatus derives Shanghai calendar days, and WXML displays a 1–3-day near-start hint or date range. Parent explicitly authorized this independent local slice while preserving the disabled read gates.

The existing native ParticipationDetailView receives one additive schedule section, using detail.record.order.ownerStartDate/ownerEndDate. It reuses OrderLifecycleTime.date, fixes the business calendar/format to Asia/Shanghai, and renders a near-start label only when both source dates are valid, end >= start, now < start and the calendar-day difference is1...3. Same-day future start is zero days, not one. Exact start, in-progress, ended or >=4days suppress the warning. Missing/malformed/reversed dates do not generate a range or reminder. A valid date range stays visible outside and alongside the reminder window.

The device clock updates the display locally each second through TimelineView. There is no request, stored timer, notification, EventKit event, upload or background work. The UI states the Shanghai/device-clock basis. This informational reminder does not decide refund or cancellation eligibility, payment state, registration status or verified progress. Those existing paths are byte-identical.

## Precise production blockers

1. `/api/registration/my-joined`: existing PlayerJourneyService.participations, authenticated POST with no form fields/body; response data is ParticipationRecord[].
2. `/api/registration/info`: existing PlayerJourneyService.detail, authenticated POST form `{id: positive registration ID}`; response is exact matching ParticipationDetail containing CmsRegistration plus cmsTopic/cmsActivity owner dates.

PlayerJourneyService initializer defaults readsEnabled=false and its private read rejects before dispatch. Normal AppSession constructs `PlayerJourneyService(configuration: $0, transport: runtimeHTTPTransport)` without an independently accepted read grant/configuration. The missing production step is an independently reviewed/issued participation-read authorization and corresponding normal composition; this increment neither creates authorization nor changes the Boolean/factory. Do not bypass it through legacy ProfileReader order reads.

The separate owned-order path remains independently gated by OwnedOrderReadApproval, including context, expiry and revocation; production issuance is explicitly blocked pending independently accepted/deployed backend null-principal guard. This is not an alternate source for this local feature. Exact endpoint/gate evidence is in production-read-blockers.json and protected-file SHA proof.

## Source differences deliberately bounded

Mini replaces the date range with the warning; native retains the range alongside it. Mini's generic date formatting can depend on device-zone parsing of explicit offsets; native consistently shows Shanghai dates, as directed. Native suppresses inverted ranges instead of generating a contradictory reminder. No backend schema or financial rule was changed.

## Integration and verification

Independent base49 increment; no earlier profile-package overlay. Additively merge the two-line mount in PlayerJourneyViews; all original lines remain exact. Four bilingual localization keys, source/test registration and dedicated DEBUG fixed-clock fixture are fragments for central integration. The fixture clearly labels production participation reads as blocked and does not use any reader or service.

22 new source assertions,10 existing owned-order composition checks,14 control-validated source mutations and8 exact-Mini fixed-clock synthetic cases pass. 28 native tests authored (16Core,6AppUnit,6UI), NOT_RUN: swift/swiftc/xcodebuild are absent. Native compile/runtime/device/UI and real-account reads remain NOT_RUN. No production operation occurred. All14 earlier seals remain byte-identical. This delivery completes the local time prompt, not a normally available production participation flow.

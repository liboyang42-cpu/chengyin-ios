# P040: source-backed creator introduction

Base: f329ff5180551ef3956b2718cb9ef071e2635409, tree e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd.

## Source and distinct gap

The sole master P040 lists loadCards, onSkip and goCreate for pages/publish/template-intro/index. At Mini commit 95e499471eaa39c28f77d16125f0cc17b8c37123, the JavaScript blob is 5a681a71fd45e17167a641776bcc2aede1a9f88e and the WXML blob is 78faa83d6a68a0da35f28ac848df2036d0773d21. The page reads POST /api/template/homeData, chooses recommended, then hot, then latest, and takes the first three rows. It exposes loading, error/retry and true-empty states, retains existing cards after a refresh failure, and allows both Begin and Skip without cards. No private Mini module enters the product patch.

The native introduction previously had static instructions and Begin only. Features 1–36 cover configuration, media, samples/rehearsals, presets, overrides, exit confirmation and saved-library navigation. Those workflows remain unchanged. The social guide is a different context with a hot-first, six-row selection rule; that rule is not reused here.

## Complete flow

The existing introduction replaces only its Begin button with TemplateAuthoringIntroExperience. Original introductory copy, naming, editing, saving, result handling and exit controls remain. The new leaf calls only the supplied DiscoveryReading.discoveryTemplateHome. Core/DiscoveryService already maps this to POST api/template/homeData. No endpoint, transport, credential, protocol requirement or grant is added.

Select one nonempty pool before taking three rows. Preserve server order, duplicates and available DTO fields. Never mix pools, invent examples or seed a draft. Cards reuse DiscoveryArtwork's credential-free HTTPS screening. Empty typed titles get an explicit localized untitled placeholder. First-load errors have a retry action; retry is single-flight. Failed refreshes retain exactly the previous real cards. A successful empty refresh clears them.

Begin and Skip share the existing naming-step continuation. Both remain available during loading, failure, empty results or unavailable readers when the owner's draft is editable. Existing unencodable draft content also does not block this navigation-only action: the data is not rewritten. Either action retires the read and advances once. No draft or storage write occurs.

Owned Tasks are cancelled on retirement, before the existing AppSession.readDiscovery cancellation check can expire an unauthorized response. Request IDs, lifecycle generations, exact owner and reader scope, draft snapshots when encodable, metadata/media revisions and model publications reject stale responses and actions. Reader publications, draft ABA, backgrounding and disappearance retire old Retry/Begin/Skip callbacks.

## Precise projection and navigation limits

DiscoveryPlayTemplate exposes title, imgUrl and other public fields, but not Mini row.name/sysCategoryList. This feature does not guess category names or alternate names. It inherits the existing DTO's validation and normalization rather than changing that contract.

Native introduction/name/editor replacement steps remain. This batch does not claim the Mini separate three-page back-stack parity and does not redo feature 35's exit guard. Existing mode, account and writer authority controls remain unchanged.

## Registration and verification

Two production sources, one App test and CreatorIntroExamples.xcstrings enter actual Xcode phases. One Core test uses unchanged Package directory discovery. Nine EN/ZH keys use the explicit CreatorIntroExamples table. The existing Begin key remains in Localizable.

Evidence separates actual pinned Mini page/helper execution, source checks, supplementary Swift grammar, PBX membership and full Git patch roundtrips. Core 9 and App 16 XCTest methods are authored. Real compilation, Core/App execution and device UI remain NOT_RUN without an Apple toolchain. Image fallback, VoiceOver, dynamic type, layout and the actual naming/editor transition still need native UI verification. This work ran no real HTTP request or content write.

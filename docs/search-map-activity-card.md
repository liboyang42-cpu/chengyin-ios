# P101 shared map activity card

## CI 138 intrinsic-height fixture correction

CI 138 at `4bf6667f8c5d9d2d59a8063d7d54eaef7a338865` reported both normal and maximum Dynamic Type card heights as exactly 20,000 points. The test passed that finite height straight to `UIHostingController.sizeThatFits(in:)`; the shared image card's `Spacer(minLength: 120)` expands to fill it. Both shipping card placements are inside `SearchMapExplorerView`'s vertical `ScrollView`, which instead measures content with an unspecified vertical proposal. This is a test-host proposal mismatch, not evidence of a 20,000-point shipping card.

The tests now use `.fixedSize(horizontal: false, vertical: true)` to request ideal height while keeping the 300-point width constraint, matching the existing `ReferenceMapCardAppTests` measurement. That reference test passed in the same CI 138 AppUnit job. The strict maximum-type height increase remains, now in English and Simplified Chinese; all measured sizes must be finite, no wider than 301 points, and below 10,000 points. A new case verifies the same content has the same intrinsic size under 10,000- and 20,000-point hosting proposals. Bilingual missing-metadata rendering uses the same bounded measurement, so filling the host can no longer falsely pass that case.

Production layout, source metadata, artwork, navigation, filters and permissions are unchanged. This correction adds one app-hosted regression case and one Python source contract. The updated Apple tests require CI/Xcode execution; cloud Python contracts and syntax parsing do not establish their runtime result.

## Source evidence

Read-only comparison against `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/searchmap/index.wxml`, blob `731e900ef0b7d3970d723ff95576c5bccd7377f5`: shared `actItem` template for the full result list and selected-object sheet. It contains source artwork, activity/theme point label, category names, activity name, real topic association, address and start/end times. It contains no price, distance, popularity or review row.
- `chengyinhub-xcx/pages/searchmap/index.js`, blob `eb6b2c97de1023b4b5407c51c5d49512639b4c36`: existing `POST /api/activity/list`; activity primary action goes to `play-activity-detail`, related-topic action uses the actual topic ID.
- `chengyinhub-xcx/utils/discover-search.js`, blob `29f262eedc7f4332b0564b243bf5d314e175fc22`: `mapPointKind` is based on `topicId`, not `productType`. Native applies its existing stricter positive JavaScript-safe linked-topic ID validation.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/PublicActivityListVO.java`, blob `4ebd2e0f84ce31694ad732075ea3397857e4e824`: source `sysCategoryList`, `address`, `topicId`, `startDate`, `endDate`; the date fields are `Date` with `@JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")`.
- `chengyinhub-framework/src/main/java/com/chengyinhub/framework/config/ApplicationConfig.java`, blob `8012b0f83d7572ec10e9f617b7a0daa794721227`: the Jackson customizer explicitly uses `Asia/Shanghai`.

The master migration document maps P101 to the native map explorer and requires shared list/map data plus PA04 missing-state and identity coverage. This slice closes the source-card metadata gap; it is not full W13–W15 completion.

## Implemented behavior

- Both ordinary map results and selected activity summaries render `SearchMapActivityCard`, reusing the established image-card primitive. All metadata remains accessible when map tiles are off. Missing coordinates do not remove list cards.
- Only `sysCategoryList.categoryName` supplies category names, kept verbatim and in source order. Missing, blank or malformed optional category decorations do not reject an otherwise valid activity. IDs/tags/alternate field names do not create names.
- A verified `linkedTopicID` supplies the theme-point label and the separate related-topic action. Primary detail remains `.activity(row.id)` and pins retain their `activity-` identity, even when a topic has the same numeric ID. Standalone activities never gain a guessed theme link.
- Source address remains an address. Missing or blank address shows an explicit unavailable message; `addressName` is not silently relabeled as a street address.
- The source start/end event window is parsed strictly from Shanghai wall time into an instant and rendered in the phone time zone with its offset. Phone-zone changes rerender the same instant. A strict date-only value retains its calendar day across zones. Missing, invalid or unverified formats show unknown independently for each endpoint.
- These are ordinary activity start/end times, not registration or payment deadlines. No deadline rules, filtering semantics, API request, pagination state, owner fence, production grant or GPS behavior change.

## Verification and acceptance boundary

Authored: 12 Core XCTest cases, 4 app-hosted XCTest cases and 9 Python source contracts. Core coverage includes verbatim category handling, malformed decorations, safe topic routing, date-only values, strict timestamp rejection, phone-zone midnight changes and DST. App-hosted coverage includes shared projection, bilingual missing states and maximum Dynamic Type width/growth.

Cloud validation passed: 18 focused card/pagination source contracts; 17 existing search/map checks; 38 existing map alternative-list checks; all contract discovery ran 2,310 cases with 2,264 passing and 46 source-dependency skips. Supplementary Tree-sitter parsing passed all 6 changed/new Swift files. These are source checks only.

Swift/Xcode compilation, XCTest execution, simulator screenshots, VoiceOver and real-device acceptance require the Apple toolchain and are not established by source checks. All 16 authored XCTest cases remain NOT_RUN.

Integration must merge the 8 bilingual keys from `Resources/SearchMapActivityCardLocalizations.fragment.json` into the main catalog and regenerate the existing Xcode project. This isolated slice deliberately does not write those shared files.

Apple acceptance still needed: open ordinary search → map → choose a manual area → search; inspect date, category, address and topic labels; select a result without enabling tiles, compare its card and open activity/related topic separately; repeat after pagination, filter change, Back, logout and account change. Verify English/Chinese, max Dynamic Type, dark/increased contrast and timezone changes. No real GPS prompt, reward, arrival or production write is needed for these checks.

# Club member public-profile navigation

The visible member-row public-profile action is now connected to the existing native public-profile destination. Current source evidence is mini-program `pages/club/detail/index.js` (`goMemberProfile`) and its active member-row WXML at private source commit `0bf8a3b13e601a82ed8b4902d775a6ed290bc26b`. The existing `api/user/public-info` adapter matches the current backend positive `member_id` input and sanitized public-profile response. No new endpoint or service grant is introduced.

Normal ClubDetailView passes its already-owned governance profile context to ClubMembersView. The list still requires sign-in and obtains a fresh club detail before member reads. A positive member ID and matching profile account/epoch are required to show the button. Navigation captures member ID and club identity, rechecks identity before rendering the destination, and clears on identity replacement. Rows without a profile context stay read-only. Existing follow/chat confirmation and write locks remain in their existing destination.

This is one bounded public-profile function. The mini-program's optional owner/admin customer-profile choice is not added by this change, and complete club-management parity is not claimed. Production composition and all live write grants remain unchanged.

Verification: four new source-contract tests; authored offline XCUITests for member profile open/back/reopen with different target IDs and sign-out while the profile is open. Aggregate static/tooling results are recorded with the review packet. No Apple compiler, XCUITest, simulator, live service or production acceptance is established here.

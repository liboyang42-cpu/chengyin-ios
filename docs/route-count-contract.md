# Route stop totals

Topic list, favorites, home route cards and topic details use the server's `locationCount` as the full-route station total. Zero remains zero. Missing, null or invalid negative values render as unknown; the client never infers a route total from the visible chapter-node projection or loads hidden details to fill it.

A chapter's displayed node count is separately labeled “Visible stops in this chapter”. Story-lock and chapter-count metadata keep their existing meanings. The decoder regression covers absent/null/negative values, zero, a total larger than the visible subset and a 64-bit count. The synthetic topic UI regression checks nine total stops despite only two visible nodes.

## Public template alignment

The verified public-template `/api/template/topic-template/list` and `/info` contracts now supply the same full-route `locationCount` aggregate. Shelf and detail share one strict nullable integer decoder and the same total-count presentation. Missing/null remains unknown; zero and the signed 64-bit range are preserved. Negative, fractional, wrong-type and overflowing values fail decoding rather than inventing zero or counting visible nodes. Listing admission, viewer-role filtering and public-projection fields are unchanged. The source contract is pinned to the separately reviewed backend revision `2bb251830b25822ddbabc72f4fabde63b81686e0`; this does not activate a live route.

These source and authored-test changes require exact-commit hosted Apple compilation and test execution. Local Python/scaffold checks do not establish native runtime acceptance.

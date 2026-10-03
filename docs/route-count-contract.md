# Route stop totals

Topic list, favorites, home route cards and topic details use the server's `locationCount` as the full-route station total. Zero remains zero. Missing, null or invalid negative values render as unknown; the client never infers a route total from the visible chapter-node projection or loads hidden details to fill it.

A chapter's displayed node count is separately labeled “Visible stops in this chapter”. Story-lock and chapter-count metadata keep their existing meanings. The decoder regression covers absent/null/negative values, zero, a total larger than the visible subset and a 64-bit count. The synthetic topic UI regression checks nine total stops despite only two visible nodes.

## Remaining endpoint alignment

Discovery route templates use `/api/template/topic-template/list`, a separate backend mapper whose aggregate semantics have not been verified against the updated topic endpoints. Its existing native presentation is intentionally unchanged. Unifying that template endpoint and its display remains open; this batch is not a claim that all route-count sources are aligned.

These source and authored-test changes require exact-commit hosted Apple compilation and test execution. Local Python/scaffold checks do not establish native runtime acceptance.

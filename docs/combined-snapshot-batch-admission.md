# Whole-input admission for the original independent snapshot gate

The old `test_original_independent_source_snapshots_remain_bound` loops over two
pinned independent source inventories. Its per-row reader previously traversed
all current readiness validation for every current AppUITests path. A bounded
180-second profile stopped during that one test, after 80 complete admissions,
133,366 byte reads and 33,804,644,290 bytes read. CPU time was 179.529 seconds.

The existing `validated_pre_run129_directory` already provides a strict batch
boundary: it hashes all current source inputs and directory membership before
admission, admits current readiness, then checks the entire source tree and the
historical directory again after the batch. No implementation of that boundary
is changed here. There is no path/mtime cache and no skipped hash predicate.

The retained test now enters that existing boundary separately for each branch
and passes each pinned file name under the admitted historical directory to the
same historical reader. Every row, original expected SHA, assertion, inventory,
method count and budget remains unchanged. The source index itself is still
hash-pinned; the regression verifies that every row is exactly in AppUITests,
that every old reader call remains present, and that all output hashes match.
The inverse of the added import and this one input-loop edit recovers the entire
old test file byte-for-byte, including every other test.

On the same bounded profiler the full original case, including setUp, passed in
47.524 seconds wall and 46.511 seconds CPU, with five complete admissions and
3,200,332,824 bytes read. Profiling overhead is included in both observations.
The baseline observation is a timeout, not a completed baseline duration. This
single-case result does not establish the complete 645-test tools suite, static
CI deadline, contracts, a source-bound completion receipt, or Apple execution.

New regression tests run in isolated copies and exercise the original complete
case, warm-cache current/historical byte changes, same-size/same-mtime mutation,
changed directory membership during the row loop, and a historical-reader
exception. Failed reads never return successful partial projections. Existing
historical materializer negative controls remain intact and are separate tests.

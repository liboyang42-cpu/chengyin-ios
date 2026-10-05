# Exact narrative-prose finding in run 81

The Gitleaks 8.24.3 gate for native commit `bcd754bd41dd41b3dad22a436211cd89ee47b657` reported one generic-api-key finding at `docs/public-template/composition-read-grant.md:75`. The matched value is the ordinary English phrase `default/missing` within a coverage-description sentence. The line contains no authentication material, generated token, account identifier or configuration value.

The source line and redacted scanner finding were inspected together. The current sentence is rephrased with equivalent coverage meaning. Since the mandatory scanner examines the full branch history, the original commit remains visible: one exact commit/path/rule/line fingerprint records this reviewed false positive. The 42 earlier commit-bound fingerprints remain unchanged.

There is no path-wide, rule-wide, current-commit, wildcard or entropy exemption. New commits and locations remain scanned. The pinned scanner, full-history command, failure exit code and required aggregate gate are unchanged. Local configuration tests validate this scope; the actual new full-history scanner result must come from the next hosted exact-SHA run.

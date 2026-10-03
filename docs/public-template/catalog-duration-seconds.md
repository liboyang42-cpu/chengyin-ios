# Catalog duration unit correction

The exact backend `TopicTemplateListItemVO.totalTime` is a nullable Long in seconds
at commit `2bb251830b25822ddbabc72f4fabde63b81686e0` (blob
`bc1aa745441b59e0563c9a10b41e48732794170a`). Its service assigns the route's
`totalTime` directly; the detail VO also declares seconds. Native catalog now
accepts a nonnegative integer and renders it with the existing bilingual
`discovery.publicSeconds` label, just like detail. There is no rounding or unit
conversion. Missing/null stays absent, explicit zero renders zero seconds, and
malformed/negative/string payloads fail decoding rather than appearing as minutes.

The retained mini-program `utils/template-display.js` at that same commit (blob
`8f9db0ea3fbe4e0439e92b50359b0f23f3db0d43`) is a legacy minute normalizer: it
strips an optional minute suffix and appends the minute unit without conversion.
The topic shelf calls it with `totalTime`, so copying that display behavior would
contradict the current typed public API. Its standalone game minute contract is
unchanged by this correction. The existing native game duration and detail rendering
are unchanged. The synthetic topic fixture now supplies 5400 seconds instead of
legacy "90 minutes" text.

This is a separately identified correction alongside the read-grant patch. Core
regressions cover unknown/zero/positive seconds, sub-minute values, large integral
values, and invalid types/units. Supplementary source checks verify the localized
seconds label. Authored Swift tests still require Apple execution; static checks
are not compiler or runtime evidence.

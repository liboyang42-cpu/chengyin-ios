# Private-home Security platform regression

The simulator-only app-hosted suite uses the real Security framework and the production primitive with a unique synthetic service and account key per test. It does not query an existing user key, use real coordinates or credentials, request new entitlements, synchronize to iCloud, or open a network connection. Cleanup is limited to exact keys for which that test successfully inserted a value.

Authored checks cover insert/read, duplicate insert without overwrite, returned value/accessibility/synchronizable attributes, wrong-tag versus matching-tag conditional deletion, and an old tag's inability to delete a replacement created by a second primitive instance.

Swift compilation and these real Security calls have not yet executed locally. The hosted simulator AppUnit gate must run this suite on the final commit. A successful simulator run does not validate real locked-device access, physical-device access groups, biometric behavior or production activation; those remain unrun separate acceptance gates.

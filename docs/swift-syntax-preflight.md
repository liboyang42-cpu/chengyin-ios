# Advisory Swift parser preflight

Status at `33f151ad170484b9e4e8cb7d9e67d3807e1b449a`: **unresolved / unsupported as a clean repository-wide gate**.

The cloud workspace has no Swift/Xcode toolchain. This optional helper uses
Tree-sitter to catch some syntax mistakes before the authoritative Apple CI run.
It is **not** the Swift compiler, typechecking, Apple API/SDK availability,
result-builder validation, linking, or runtime/UI evidence. A clean parse does
not establish any of those properties. Grammar recovery can also reject valid
Swift. Do not rewrite app code simply to satisfy this third-party grammar.

## Setup in a workspace-local environment

The lock is intentionally for CPython 3.12 on Linux glibc x86_64, the environment
verified here. Both packages are upstream-maintained packages from the official
PyPI registry; the Swift grammar is a community project, not an Apple parser.
Only the verified binary wheel hashes are allowed. Other interpreters/platforms
need separately reviewed official wheel hashes; do not bypass hash verification
or fall back to a source build to make this lock install.

From the repository root, place the environment outside the checkout:

```sh
python3.12 -m venv ../swift-syntax-venv
../swift-syntax-venv/bin/python -m pip --isolated install \
  --index-url https://pypi.org/simple --no-cache-dir \
  --only-binary=:all: --no-deps --require-hashes \
  -r tools/requirements-swift-syntax.txt
../swift-syntax-venv/bin/python -m unittest discover \
  -s tools/advisory_tests -p test_swift_syntax.py -v
../swift-syntax-venv/bin/python tools/check_swift_syntax.py
```

If registry access is denied, stop and report the restriction. No alternative
mirror, proxy, global pip configuration, credentials, or OS changes are needed.
The checker itself is offline and does not install anything.

Default discovery includes all Git-tracked and non-ignored untracked `.swift`
files, including `Package.swift` and tests. Build outputs and dependencies ignored
by Git are not inputs. Explicit paths are relative to `--root` (the script's
checkout by default), or may be absolute:

```sh
../swift-syntax-venv/bin/python tools/check_swift_syntax.py App/SessionHomeFeedView.swift
../swift-syntax-venv/bin/python tools/check_swift_syntax.py --root ../chengyin-ios
```

Exit codes:

- `0`: selected bytes contain no Tree-sitter recovery nodes; scope still parser-only
- `1`: at least one `ERROR` or `MISSING` node, including potential grammar limitations
- `2`: dependency/version, input, encoding, or execution failure

Diagnostics use one-based line and UTF-8 byte-column positions. All recovery
nodes are reported, including anonymous missing punctuation and zero-width
errors. There is no ignored-file list, baseline suppression, preprocessing,
source normalization, or success-on-empty behavior.

## Verification at the recorded revision

On 2026-10-01, Python 3.12.14, tree-sitter 0.26.0, tree-sitter-swift 0.7.3:

- 14 focused Python helper tests passed, including dependency failure, version
  drift, Git discovery, invalid encoding, recovery nodes, and CLI exit codes
- All 27 Python tooling tests passed with the same pinned environment
- The exact previous `SessionHomeFeedView.swift` from `33f151a^` failed at
  line 39, byte-column 23, where `} ToolbarItem` joins two separate calls
- The corrected `App/SessionHomeFeedView.swift` at `33f151a` parsed with no recovery
- The full 252-file repository scan returned **1**, with **10 diagnostics in
  6 files**; the initial parser loop took approximately 0.51 seconds
- No Swift compiler, Xcode, simulator, Apple API, or runtime check ran here

Reproduce the exact historical regression without changing the working source:

```sh
git show '33f151a^:App/SessionHomeFeedView.swift' > ../SessionHomeFeedView-before-33f151a.swift
../swift-syntax-venv/bin/python tools/check_swift_syntax.py ../SessionHomeFeedView-before-33f151a.swift
# Expected: exit 1, ERROR at 39:23
../swift-syntax-venv/bin/python tools/check_swift_syntax.py App/SessionHomeFeedView.swift
# Expected: exit 0 for this selected file only
```

### Unresolved grammar coverage

The following minimal constructs independently reproduce the findings with the
pinned packages; the original repository sources are not modified:

| Files / one-based lines | Construct | Tree-sitter result |
| --- | --- | --- |
| `App/AuthChannelView.swift:73`, `App/RegistrationSheetView.swift:136` | `footer:` trailing closure begins on the following line | `ERROR` at label |
| `App/MerchantHomeView.swift:193`, `App/MessagingComponents.swift:40` | `icon:` trailing closure begins on the following line | `ERROR` at label |
| `Core/RegistrationUIForm.swift:34,36` | `#if DEBUG` / `#endif` between enum cases | zero-width `ERROR` nodes |
| `Tests/CoreTests/ParticipantCoordinatorTests.swift:56,157,196,226` | `resume?.resume(returning: ())` | invented `MISSING !` at the empty tuple |

These are grammar-coverage limitations inferred from valid Swift forms, minimal
reproductions, and the parser's recovery output, not new compiler failures.
For example, Swift's accepted
[multiple trailing closures proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0279-multiple-trailing-closures.md)
permits labeled trailing closures; the pinned grammar parses the same minimal
call when the label remains on the preceding line, but not on its own next line.
The helper tests preserve failures for these forms so a dependency upgrade needs
an explicit coverage review. Apple CI must resolve compiler correctness; do not
turn these diagnostics into an ignored-file allowlist or a false clean result.

## Integration decision

The candidate consists only of this document, `tools/check_swift_syntax.py`,
`tools/requirements-swift-syntax.txt`, and `tools/advisory_tests/test_swift_syntax.py`.
No workflow, app source, project file, or existing checker is changed.

Run it as an explicit advisory investigation for now, and record exit 1 as
unresolved instead of hiding it with `|| true` or counting it as a pass. Do not
make the full-tree command a required green CI gate with the current grammar.
Keep the existing Swift/Xcode checks authoritative.

The focused tests deliberately require the pinned dependencies and fail if they
are absent. Before adding this test module to normal unittest discovery, choose
a dedicated pinned Python environment for that invocation (or keep the candidate
unintegrated). Installing dependencies in the main CI workflow is a separate
decision; this candidate does not add an installation step there.

## Provenance and lock

Verified upstream project pages and package files on 2026-10-01:

- [tree-sitter 0.26.0 on PyPI](https://pypi.org/project/tree-sitter/0.26.0/),
  [upstream Python binding](https://github.com/tree-sitter/py-tree-sitter)
- [tree-sitter-swift 0.7.3 on PyPI](https://pypi.org/project/tree-sitter-swift/0.7.3/),
  [upstream Swift grammar](https://github.com/alex-pinkus/tree-sitter-swift)
- [Tree-sitter Node API](https://tree-sitter.github.io/py-tree-sitter/classes/tree_sitter.Node.html)
  documents error nodes and missing nodes inserted during recovery

Installed wheels (no source build or transitive packages):

1. [tree_sitter-0.26.0-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl](https://files.pythonhosted.org/packages/8a/2f/6e6781b31677231366cb3cf27bc8269157f6d4b03c9032865a4f5f2bbe7e/tree_sitter-0.26.0-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl)
   SHA-256: `5a6b333b0282d8bb0af741f9b018bd2523d4eecb2686bf6717066a625fecfaa4`
2. [tree_sitter_swift-0.7.3-cp38-abi3-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl](https://files.pythonhosted.org/packages/e1/9a/55f6cc9aad9079facf166d616472fd8e05007cbee9c62b749e153bf0521d/tree_sitter_swift-0.7.3-cp38-abi3-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl)
   SHA-256: `f38feeb4f7350c8b30d567a0dc08bf1eeaa67c241b6888d72a45a8b1a4aa7187`

These are the wheel archive hashes reported by the official PyPI installation,
then checked again by a successful `--require-hashes` reinstall from the lock,
not hashes of the expanded environment or an attestation of Apple compatibility.

## Integration decision

The parser tests live in tools/advisory_tests and run only in the separately pinned Linux parser environment. Normal Apple CI tooling discovery remains in tools/tests and has no parser dependency. This is not an exclusion of product tests: the advisory parser cannot accurately recognize all valid Swift constructs and is not a required passing gate. Every full-tree finding remains visible and nonzero. Swift compilation on the Apple runner remains authoritative.

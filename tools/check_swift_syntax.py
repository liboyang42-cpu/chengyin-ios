#!/usr/bin/env python3
"""Strict, supplementary Tree-sitter diagnostics; NOT Swift compiler evidence.

Exit 0: the selected bytes have no Tree-sitter recovery nodes.
Exit 1: at least one ERROR/MISSING node (possibly a grammar limitation).
Exit 2: dependency, input, encoding, or execution failure.
See docs/swift-syntax-preflight.md before treating this as a gate.
"""

import argparse
import importlib.metadata
import pathlib
import subprocess
import sys
from typing import NamedTuple


ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSIONS = {"tree-sitter": "0.26.0", "tree-sitter-swift": "0.7.3"}
SCOPE = (
    "SCOPE: supplementary Tree-sitter parse only; no Swift typechecking, "
    "Apple SDK/API checks, compilation, or runtime tests. Grammar gaps may fail valid Swift."
)


class PreflightError(Exception):
    """The check could not inspect all requested inputs."""


class Diagnostic(NamedTuple):
    kind: str
    line: int
    byte_column: int
    node_type: str


def make_parser():
    """Require the exact, tested package pair rather than silently drifting."""
    try:
        for distribution, expected in VERSIONS.items():
            actual = importlib.metadata.version(distribution)
            if actual != expected:
                raise PreflightError(f"{distribution}=={expected} required; found {actual}")
        from tree_sitter import Language, Parser
        import tree_sitter_swift

        return Parser(Language(tree_sitter_swift.language()))
    except (ImportError, importlib.metadata.PackageNotFoundError) as error:
        raise PreflightError(
            "missing parser dependency; install tools/requirements-swift-syntax.txt "
            "as described in docs/swift-syntax-preflight.md"
        ) from error
    except (TypeError, ValueError, OSError) as error:
        raise PreflightError(f"cannot initialize parser: {error}") from error


def parse_source(parser, source: bytes) -> list[Diagnostic]:
    """Inspect the original UTF-8 bytes without rewriting or suppressing failures."""
    try:
        source.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PreflightError(f"source is not valid UTF-8: {error}") from error
    tree = parser.parse(source)
    if tree is None:
        raise PreflightError("parser returned no syntax tree")
    diagnostics = []
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.is_error or node.is_missing:
            diagnostics.append(Diagnostic(
                "MISSING" if node.is_missing else "ERROR",
                node.start_point.row + 1,
                node.start_point.column + 1,
                node.type,
            ))
        # Include anonymous children: missing punctuation can be unnamed.
        # Keep zero-width ERROR nodes and continue through error-node children.
        if node.has_error:
            stack.extend(reversed(node.children))
    if tree.root_node.has_error and not diagnostics:
        raise PreflightError("tree reports recovery without an identifiable diagnostic")
    return diagnostics


def swift_paths(root: pathlib.Path, requested: list[str]) -> list[pathlib.Path]:
    """By default inspect tracked and non-ignored untracked Swift files via Git."""
    if requested:
        names = requested
    else:
        try:
            result = subprocess.run(
                ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others",
                 "--exclude-standard", "--", "*.swift"],
                check=True, capture_output=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise PreflightError(f"cannot discover Swift files using git: {error}") from error
        names = [name.decode("utf-8") for name in result.stdout.split(b"\0") if name]
    paths = set()
    for name in names:
        path = pathlib.Path(name)
        if not path.is_absolute():
            path = root / path
        if path.suffix != ".swift" or not path.is_file():
            raise PreflightError(f"expected an existing .swift file: {path}")
        paths.add(path.resolve())
    if not paths:
        raise PreflightError("no Swift files found; refusing an empty success")
    return sorted(paths)


def main(argv=None) -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--root", type=pathlib.Path, default=ROOT,
                     help="repository root (defaults to this script's checkout)")
    cli.add_argument("paths", nargs="*", help="optional .swift files, relative to --root")
    args = cli.parse_args(argv)
    root = args.root.resolve()
    try:
        parser = make_parser()
        paths = swift_paths(root, args.paths)
        failed = 0
        count = 0
        for path in paths:
            try:
                diagnostics = parse_source(parser, path.read_bytes())
            except (OSError, PreflightError) as error:
                raise PreflightError(f"{path}: {error}") from error
            failed += bool(diagnostics)
            count += len(diagnostics)
            display = path.relative_to(root) if path.is_relative_to(root) else path
            for diagnostic in diagnostics:
                print(f"{display}:{diagnostic.line}:{diagnostic.byte_column}: "
                      f"tree-sitter {diagnostic.kind} ({diagnostic.node_type})")
        status = "FAIL" if failed else "PASS"
        print(f"{status} Tree-sitter parse: {len(paths)} Swift files, "
              f"{failed} files with recovery, {count} diagnostics")
        print("VERSIONS: " + ", ".join(f"{name}=={version}" for name, version in VERSIONS.items()))
        print(SCOPE)
        return 1 if failed else 0
    except (PreflightError, UnicodeDecodeError) as error:
        print(f"ERROR Swift parser preflight: {error}", file=sys.stderr)
        print(SCOPE, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Move this run's unsigned build-for-testing Products without losing permissions.

Apple TN2339 documents -xctestrun test-without-building and __TESTROOT__ paths.
Same-run artifacts are commit/toolchain/hash checked; missing products fail closed.
"""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tarfile

TARGETS = {'QuestifyUITests': 'UI_XCTESTRUN', 'QuestifyAppUnitTests': 'APP_UNIT_XCTESTRUN'}
MANIFEST = 'questify-test-products.json'


def toolchain():
    return {'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            'developer': subprocess.check_output(['xcode-select', '-p'], text=True).strip()}


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def normalize_paths(value, products):
    if isinstance(value, dict):
        return {key: normalize_paths(child, products) for key, child in value.items()}
    if isinstance(value, list):
        return [normalize_paths(child, products) for child in value]
    if isinstance(value, str):
        # macOS commonly exposes the same temporary directory through /var and
        # /private/var. Preserve both the caller's spelling and canonical root.
        aliases = {str(pathlib.Path(products).absolute()), str(pathlib.Path(products).resolve())}
        for prefix in sorted(aliases, key=len, reverse=True):
            if value == prefix:
                value = '__TESTROOT__'
            value = value.replace(prefix + '/', '__TESTROOT__/')
        return value
    return value


def inventory(products, normalize=False):
    source_root = pathlib.Path(products).absolute()
    products = source_root.resolve()
    found = {target: [] for target in TARGETS}
    for path in sorted(products.glob('*.xctestrun')):
        with path.open('rb') as source:
            data = plistlib.load(source)
        if normalize:
            data = normalize_paths(data, source_root)
            with path.open('wb') as destination:
                plistlib.dump(data, destination)
        for node in walk(data):
            bundle = node.get('TestBundlePath')
            if not isinstance(bundle, str):
                continue
            target = pathlib.PurePosixPath(bundle).stem
            if target not in TARGETS:
                continue
            for key in ['TestBundlePath', 'TestHostPath', 'UITargetAppPath']:
                value = node.get(key)
                if isinstance(value, str) and value.startswith('/'):
                    raise ValueError(f'Nonportable {key} in {path.name}')
            found[target].append(path.name)
    result = {}
    for target, paths in found.items():
        unique = set(paths)
        if len(unique) != 1:
            raise ValueError(f'Expected exactly one xctestrun for {target}, got {sorted(unique)}')
        result[target] = unique.pop()
    if not (products / 'Debug-iphonesimulator/Questify.app').is_dir():
        raise ValueError('Compiled simulator app is missing')
    return result


def pack(products, archive, commit, identity):
    source_root = pathlib.Path(products).absolute()
    products = source_root.resolve()
    archive = pathlib.Path(archive).resolve()
    if not commit or len(commit) != 40 or any(c not in '0123456789abcdef' for c in commit):
        raise ValueError('Exact commit SHA required')
    manifest = {'commit': commit, 'toolchain': identity, 'targets': inventory(source_root, normalize=True)}
    (products / MANIFEST).write_text(json.dumps(manifest, sort_keys=True) + '\n')
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'w:gz', compresslevel=1) as output:
        output.add(products, arcname='Products')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(archive.suffix + '.sha256').write_text(digest + '\n')
    return manifest


def restore(archive, destination, commit, identity):
    archive, destination = pathlib.Path(archive).resolve(), pathlib.Path(destination).resolve()
    expected = archive.with_suffix(archive.suffix + '.sha256').read_text().strip()
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise ValueError('Test product archive hash mismatch')
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('Restore destination must be empty')
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:gz') as source:
        for member in source.getmembers():
            name = pathlib.PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or not name.parts or name.parts[0] != 'Products':
                raise ValueError('Unexpected archive path')
        source.extractall(destination, filter='data')
    products = destination / 'Products'
    manifest = json.loads((products / MANIFEST).read_text())
    if manifest.get('commit') != commit or manifest.get('toolchain') != identity:
        raise ValueError('Test products belong to another commit or Apple toolchain')
    if inventory(products) != manifest.get('targets'):
        raise ValueError('Test product target inventory mismatch')
    return {TARGETS[target]: str(products / path) for target, path in manifest['targets'].items()}


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='action', required=True)
    create = sub.add_parser('pack')
    create.add_argument('--products', required=True)
    create.add_argument('--archive', required=True)
    create.add_argument('--commit', required=True)
    extract = sub.add_parser('restore')
    extract.add_argument('--archive', required=True)
    extract.add_argument('--destination', required=True)
    extract.add_argument('--commit', required=True)
    extract.add_argument('--github-env', required=True)
    args = parser.parse_args()
    if args.action == 'pack':
        manifest = pack(args.products, args.archive, args.commit, toolchain())
        print('Prepared unsigned test products for', manifest['commit'], sorted(manifest['targets']))
    else:
        values = restore(args.archive, args.destination, args.commit, toolchain())
        with pathlib.Path(args.github_env).open('a') as output:
            for key, value in sorted(values.items()):
                if '\n' in value or '\r' in value:
                    raise ValueError('Invalid output path')
                output.write(f'{key}={value}\n')
        print('Verified same-commit, same-toolchain test products:', sorted(values))


if __name__ == '__main__':
    main()

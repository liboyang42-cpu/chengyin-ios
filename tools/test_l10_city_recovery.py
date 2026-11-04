#!/usr/bin/env python3
"""Run focused Swift XCTest on Linux; no network service or Apple build is exercised.

Copies the selected production city/action sources and XCTest file unchanged.
The projection suite does not import the Observation coordinator; the recovery suite
compiles and tests that coordinator when the host supports its Observation runtime.
Extracts read DTOs, their two validators, and market/language enums unchanged from
larger files to avoid importing the unrelated app runtime. No fake implementation
replaces city logic. SWIFT_EXECUTABLE may identify an installed Swift toolchain.
"""
import os
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    index = opening + 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index] + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['recovery', 'projection'], default='recovery')
    suite = parser.parse_args().suite
    swift = os.environ.get('SWIFT_EXECUTABLE', 'swift')
    with tempfile.TemporaryDirectory(prefix='l10-city-') as tmp:
        root = Path(tmp)
        core = root / 'Sources' / 'QuestifyCore'
        tests = root / 'Tests' / 'QuestifyCoreTests'
        core.mkdir(parents=True)
        tests.mkdir(parents=True)
        (root / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QuestifyCore", targets: [
    .target(name: "QuestifyCore"),
    .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])
])
''')
        sources = ['CityActionContract', 'CityGameBoardProjection', 'CityDeltaStream', 'ReformWorldCapabilities']
        if suite == 'recovery':
            sources += ['CityActionRecoveryJournal', 'CityGameCoordinator']
        for name in sources:
            shutil.copyfile(ROOT / 'Core' / (name + '.swift'), core / (name + '.swift'))
        read = (ROOT / 'Core/CityPlayerReading.swift').read_text()
        dtos = 'import Foundation\n'
        for signature in ['public enum CityMembership:', 'public struct CityReadBoard:',
                          'public struct CityReadPoint:', 'public struct CityParticipation:',
                          'public struct CityReadSnapshot:']:
            dtos += declaration(read, signature)
        dtos += 'enum CityReadRoute {\n'
        for signature in ['    static func validID(', '    static func validLabel(']:
            dtos += declaration(read, signature)
        dtos += '}\n'
        dtos += declaration((ROOT / 'Core/RegionalConfiguration.swift').read_text(), 'public enum RegionalMarket:')
        dtos += declaration((ROOT / 'Core/AppPreferences.swift').read_text(), 'public enum AppLanguage:')
        (core / 'ExtractedCityReadDeclarations.swift').write_text(dtos)
        test_name = 'CityGameCoordinatorTests.swift' if suite == 'recovery' else 'CityGameProjectionTests.swift'
        shutil.copyfile(ROOT / 'Tests/CoreTests' / test_name, tests / test_name)
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(root / 'clang-cache'), XDG_CACHE_HOME=str(root / 'cache'))
        subprocess.run([swift, 'test', '--package-path', tmp, '--scratch-path', str(root / '.build'),
                        '--cache-path', str(root / 'cache'), '--config-path', str(root / 'config'),
                        '--security-path', str(root / 'security')], check=True, env=env)


if __name__ == '__main__':
    main()

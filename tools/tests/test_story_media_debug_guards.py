"""Build-boundary source checks only; these do not execute XCTest or an Apple compiler."""
import hashlib
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
COUNTS = {
    'ProjectStoryImagePresentationTests.swift': 13,
    'ProjectStoryImageCompositionTests.swift': 5,
    'ProjectStoryAudioPresentationTests.swift': 11,
    'ProjectStoryAudioCompositionTests.swift': 6,
    'ProjectStoryAudioDocumentTests.swift': 8,
    'ProjectPendingStoryMediaTests.swift': 8,
}
RELEASE_DOCUMENT_METHODS = {
    'testDefaultOffNeverPresentsOrReads',
    'testOneDocumentAndCancelKeepNoCopiedBody',
    'testInvalidSelectionCountNeverStartsReader',
    'testActualReaderUsesCoordinatedProviderURLAndExactBytesAndName',
    'testActualReaderRejectsSymlinkDirectoryEmptyAndTooLargeFiles',
}


def active_source(text, debug):
    active = [True]
    result = []
    for line in text.splitlines(keepends=True):
        directive = line.strip()
        if directive == '#if DEBUG':
            active.append(active[-1] and debug)
        elif directive == '#endif':
            if len(active) == 1:
                raise AssertionError('unmatched conditional guard')
            active.pop()
        elif directive.startswith(('#if ', '#elseif ', '#else')):
            raise AssertionError('unexpected condition in these narrowly inventoried files')
        elif active[-1]:
            result.append(line)
    if len(active) != 1:
        raise AssertionError('unterminated conditional guard')
    return ''.join(result)


class StoryMediaDebugGuards(unittest.TestCase):
    def source(self, filename):
        return (ROOT / 'Tests/AppUnitTests' / filename).read_text()

    def test_debug_retains_all_fifty_one_methods_once(self):
        for filename, count in COUNTS.items():
            source = self.source(filename)
            original = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            active = re.findall(r'\bfunc\s+(test\w+)\s*\(', active_source(source, True))
            self.assertEqual(len(original), count, filename)
            self.assertEqual(active, original, filename)
            self.assertEqual(len(set(active)), count, filename)

    def test_release_has_no_debug_fixture_reference_and_keeps_five_independent_reader_methods(self):
        for filename in COUNTS:
            source = active_source(self.source(filename), False)
            self.assertNotIn('ProjectStoryImageSynthetic', source, filename)
            self.assertNotIn('ProjectStoryAudioSynthetic', source, filename)
            methods = set(re.findall(r'\bfunc\s+(test\w+)\s*\(', source))
            expected = RELEASE_DOCUMENT_METHODS if filename == 'ProjectStoryAudioDocumentTests.swift' else set()
            self.assertEqual(methods, expected, filename)

    def test_existing_debug_only_target_prerequisite_is_present_in_generator_and_actual_project(self):
        generator = (ROOT / 'tools/generate_project.py').read_text()
        self.assertIn("**({'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)'} if name=='Debug' else {})", generator)
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        for configuration in ['Debug', 'Release']:
            ident = hashlib.sha256(('unit' + configuration).encode()).hexdigest()[:24].upper()
            block = project.split('"' + ident + '" = {', 1)[1].split('\n\t\t};', 1)[0]
            self.assertIn('"name" = "' + configuration + '";', block)
            if configuration == 'Debug':
                self.assertIn('"SWIFT_ACTIVE_COMPILATION_CONDITIONS" = "DEBUG $(inherited)";', block)
            else:
                self.assertNotIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS', block)
        config = (ROOT / 'Config/AppUnitTests.xcconfig').read_text()
        self.assertNotRegex(config, r'(?m)^SWIFT_ACTIVE_COMPILATION_CONDITIONS\s*=.*DEBUG')


if __name__ == '__main__':
    unittest.main()

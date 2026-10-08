"""Source-text checks only; no Swift execution, real image validation or upload."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SquareUploadBackendLimitSourceTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def service(self):
        return self.read('Core/SquareWorkspaceService.swift')

    def upload_request(self):
        return self.service().split('public func uploadRequest(', 1)[1].split('public func upload(', 1)[0]

    def test_file_part_guard_is_inclusive_ten_mib_and_precedes_request_construction(self):
        source = self.service()
        request = self.upload_request()
        self.assertRegex(source, r'public static let maximumUploadImageBytes\s*=\s*10\s*\*\s*1024\s*\*\s*1024\b')
        guard = 'guard !bytes.isEmpty, bytes.count <= Self.maximumUploadImageBytes,'
        self.assertIn(guard, request)
        self.assertIn('else { throw SquareWorkspaceFailure.invalid }', request)
        self.assertLess(request.index(guard), request.index('var r = try request('))
        self.assertNotIn('12 * 1024 * 1024', request)
        self.assertNotRegex(request, r'maximumUploadImageBytes\s*-')

    def test_upload_mime_allowlist_and_filename_extensions_are_only_jpeg_and_png(self):
        request = self.upload_request()
        match = re.search(r'\[([^\]]+)\]\.contains\(mimeType\)', request)
        self.assertIsNotNone(match)
        self.assertEqual(re.findall(r'"([^"]+)"', match.group(1)), ['image/jpeg', 'image/png'])
        self.assertIn('let ext = mimeType == "image/png" ? "png" : "jpg"', request)
        for unsupported in ['image/webp', 'image/gif', 'video/', 'audio/']:
            self.assertNotIn(unsupported, request)

    def test_app_uses_the_service_limit_without_its_own_larger_allowance(self):
        host = self.read('App/SquareWorkspaceView.swift')
        self.assertEqual(host.count('maximumImageBytes: SquareWorkspaceService.maximumUploadImageBytes'), 1)
        self.assertNotRegex(host, r'maximumImageBytes:\s*\d')

    def test_inspector_accepts_only_jpeg_png_and_still_checks_actual_content_type(self):
        inspector = self.read('App/SquarePostLocalMediaInspector.swift')
        match = re.search(r'static let imageTypes:\s*\[UTType\]\s*=\s*\[([^\]]+)\]', inspector)
        self.assertIsNotNone(match)
        self.assertEqual(re.findall(r'\.([A-Za-z]+)', match.group(1)), ['jpeg', 'png'])
        self.assertIn('provider.hasItemConformingToTypeIdentifier($0.identifier)', inspector)
        self.assertIn('guard maximumBytes > 0, imageTypes.contains(type)', inspector)
        self.assertIn('guard imageTypes.contains(expectedType),', inspector)
        self.assertIn('actualType == expectedType', inspector)
        self.assertIn('CGImageSourceCreateThumbnailAtIndex', inspector)
        self.assertNotIn('jpegData(', inspector)
        self.assertNotIn('pngData(', inspector)
        presentation = self.read('App/SquarePostLocalMediaPresentation.swift')
        self.assertIn('Choose a JPEG or PNG image, or remove this selection.', presentation)
        self.assertIn('请选择 JPEG 或 PNG 图片，或移除此选择。', presentation)
        self.assertNotIn('WebP', presentation)

    def test_single_file_multipart_and_community_receipt_lane_are_preserved(self):
        request = self.upload_request()
        self.assertIn('request("POST", "api/common/uploadOSS", token: token)', request)
        self.assertEqual(request.count('name=\\"file\\"'), 1)
        self.assertIn('filename=\\"image.\\(ext)\\"', request)
        self.assertIn('Content-Type: \\(mimeType)', request)
        self.assertIn('if communityProof { body.append(', request)
        self.assertIn('name=\\"bizType\\"', request)
        self.assertIn('COMMUNITY_POST', request)
        self.assertIn('body.append(bytes)', request)
        self.assertNotIn('X-Idempotency-Key', request)

    def test_authorization_and_mutation_unknown_semantics_remain_in_send(self):
        source = self.service()
        send = source.split('private func send(', 1)[1].split('private func objectData(', 1)[0]
        self.assertIn('try Task.checkCancellation(); try authorize()', send)
        self.assertIn('do { response = try await transport.send(r) } catch { throw mutation ? SquareWorkspaceFailure.unknown : error }', send)
        self.assertIn('do { try authorize() } catch { throw mutation ? SquareWorkspaceFailure.unknown : error }', send)
        self.assertIn('guard !Task.isCancelled else { throw mutation ? SquareWorkspaceFailure.unknown : CancellationError() }', send)
        self.assertIn('throw mutation ? SquareWorkspaceFailure.unknown : SquareWorkspaceFailure.malformed', send)
        upload = source.split('public func upload(', 1)[1].split('public func acknowledge(', 1)[0]
        self.assertIn('send(uploadRequest(bytes: bytes, mimeType: mimeType, communityProof: communityProof, token: token), mutation: true)', upload)
        self.assertIn('if communityProof && !media.hasProof { throw SquareWorkspaceFailure.missingMediaProof }', upload)

    def test_video_stays_unavailable_before_inspection_and_existing_grants_remain(self):
        presentation = self.read('App/SquarePostLocalMediaPresentation.swift')
        branch = 'if kind == .video { state = .videoUnavailable; return nil }'
        self.assertIn(branch, presentation)
        self.assertLess(presentation.index(branch), presentation.index('selection.beginInspection(id)'))
        self.assertIn('!coordinator.grants.live || !coordinator.grants.media', self.read('App/SquareWorkspaceView.swift'))

    def test_authored_swift_tests_cover_limits_and_no_transport_without_claiming_content_validation(self):
        tests = self.read('Tests/CoreTests/SquareWorkspaceTests.swift')
        for token in ['testUploadFilePartLimitMatchesTenMiBWithoutSubtractingMultipartOverhead',
                      'testUnsupportedTypesAndInvalidSizesAreRejectedBeforeTransport',
                      'testSupportedImageExtensionsAndEmptyPayloadGuard',
                      'count: limit + 1', 'XCTAssertGreaterThan(body.count, limit)',
                      'XCTAssertLessThan(body.count, 20 * 1024 * 1024)',
                      'XCTAssertTrue(transport.requests.isEmpty)',
                      'Synthetic bytes only exercise request construction, never real image validity.']:
            self.assertIn(token, tests)


if __name__ == '__main__':
    unittest.main()

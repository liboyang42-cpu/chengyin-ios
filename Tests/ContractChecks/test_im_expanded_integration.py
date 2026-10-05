"""Additive source evidence. Not Swift compilation or runtime parity."""
import json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class IMExpandedIntegrationTests(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_concrete_http_adapter_has_default_off_and_exact_wire(self):
        s=self.read('Core/IMExpandedService.swift')
        self.assertIn('writesEnabled: Bool = false',s)
        self.assertIn('guard writesEnabled else',s);self.assertIn('enabledPaths?.contains("api/common/uploadOSS") ?? true',s)
        self.assertIn('transport.send(request)',s)
        for field in ['target_member_id','conversation_id','client_message_id','muted','uploadOSS']:
            self.assertIn(field,s)
        self.assertIn('name=\\"file\\"',s)
    def test_normal_account_host_wires_optional_context(self):
        self.assertIn('expanded:session.imExpandedNavigation',self.read('App/AccountView.swift'))
        self.assertIn('IMStartConversationView',self.read('App/MessagingHomeView.swift'))
        self.assertIn('IMConversationControlsView',self.read('App/MessagingHistoryView.swift'))
        self.assertIn('IMImageComposeView',self.read('App/IMExpandedViews.swift'))
    def test_stable_scope_and_dormant_session(self):
        s=self.read('App/AppSession.swift')
        part=s[s.index('private var imExpandedCoordinators:'):s.index('private let messagingService:')]
        self.assertIn('[IMScope: IMExpandedCoordinator]',part)
        self.assertIn('IMExpandedWriter(service: nil',part)
        self.assertIn('epoch: gate.currentStamp',part)
        self.assertIn('retainedImagePickerHost.imPicker(scope: scope',part)
        self.assertIn('var nativeSelectionEnabled = false',(ROOT/'App/RetainedImagePresenterHost.swift').read_text())
        self.assertNotIn('UUID()',part)
    def test_fixture_bypasses_production_session(self):
        self.assertEqual(self.read('App/QuestifyApp.swift').count('contains("--im-expanded-fixture")'),2)
        self.assertIn('--im-expanded-fixture',self.read('Tests/AppUITests/IMExpandedUITests.swift'))
    def test_card_actions_use_typed_routes_and_trusted_sender(self):
        self.assertIn('message.senderID == 0',self.read('Core/IMExpandedContracts.swift'))
        s=self.read('App/MessagingMessageDetailView.swift')
        self.assertIn('if message.senderID == 0, let result',s)
        self.assertIn('TopicDetailView(id: id',s)
        self.assertNotIn('openURL',s)
    def test_upload_is_not_automatic_send_and_no_device_provider(self):
        s=self.read('Core/IMMediaSelection.swift')
        self.assertIn('case .uploading, .outcomeUnknown: state = .outcomeUnknown',s)
        self.assertNotIn('writer.perform(',s)
        self.assertIn('public final class IMDormantImagePicker',s)
        self.assertNotIn('AVFoundation',self.read('App/IMExpandedViews.swift'))
    def test_existing_image_preview_remains_in_host(self):
        self.assertIn('SocialMessageMediaView(message: message',self.read('App/MessagingMessageDetailView.swift'))
    def test_bilingual_keys_present(self):
        catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        expected=json.loads(self.read('docs/im-expanded-localizations.json'))
        for key in expected: self.assertEqual(set(catalog[key]['localizations']),{'en','zh-Hans'})
    def test_no_im_voice_or_socket_feature_claim(self):
        for path in ['App/IMExpandedViews.swift','Core/IMExpandedService.swift']:
            s=self.read(path)
            self.assertNotIn('URLSessionWebSocketTask',s)
            self.assertNotIn('AVAudioRecorder',s)
            self.assertNotIn('voiceMessage',s)

"""Regression guards for identifier inheritance seen in actual Apple UI failures."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class IdentifierBoundaryTests(unittest.TestCase):
    def test_square_retry_not_overridden_by_container_identifier(self):
        source=(ROOT/'App/SquareComponents.swift').read_text()
        self.assertIn('Button("square.retry", action: retry).accessibilityIdentifier("square.retry")',source)
        self.assertNotIn('}.accessibilityIdentifier("square.error")',source)
    def test_collection_retry_not_overridden_by_ancestor(self):
        source=(ROOT/'App/AccountCollectionComponents.swift').read_text()
        self.assertNotIn('}.padding(.vertical, 10).accessibilityIdentifier',source)
        self.assertNotIn('.accessibilityIdentifier("accountCollection.favorites.moreError")',(ROOT/'App/AccountCollectionFavoritesView.swift').read_text())
    def test_ticket_notice_query_targets_text_not_decorative_image(self):
        self.assertIn('reveal(app.staticTexts["ticketWallet.redemption.notice"])',(ROOT/'Tests/AppUITests/TicketWalletFlowTests.swift').read_text())
    def test_raw_translation_key_assertion_checks_label(self):
        self.assertIn('NSPredicate(format: "label == %@", "square.empty")',(ROOT/'Tests/AppUITests/SquareFlowTests.swift').read_text())

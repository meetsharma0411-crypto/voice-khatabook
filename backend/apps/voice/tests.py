import json
from datetime import date
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.catalog.models import Product, ProductAlias, ProductPrice
from apps.customers.models import Customer
from apps.khata.models import LedgerEntry, SimpleKhataEntry

from .models import BusinessKnowledge, VoiceProposal
from .services import evaluate_extraction, validate_extraction


@override_settings(DJANGO_DEBUG=False)
class VoiceProposalTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username="voice-user", password="test-pass")
        self.customer = Customer.objects.create(name="Ramesh Patel", mobile_number="9876543210")
        self.product = Product.objects.create(name="Milk", default_unit="litre", is_active=True)
        ProductAlias.objects.create(product=self.product, alias="dudh", language="hinglish")
        ProductAlias.objects.create(product=self.product, alias="દૂધ", language="gu")
        ProductPrice.objects.create(product=self.product, price=Decimal("36.00"), effective_from=date(2020, 1, 1))
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    @staticmethod
    def extraction(**overrides):
        data = {
            "customer_name": "Ramesh Patel",
            "transaction_type": "udhaar",
            "items": [],
            "amount": Decimal("200.00"),
            "language": "hinglish",
            "confidence": Decimal("0.96"),
        }
        data.update(overrides)
        return data

    def test_extraction_uses_decimal_and_validates_positive_quantity(self):
        parsed = validate_extraction(json.dumps({
            "customer_name": "Ramesh Patel", "transaction_type": "udhaar",
            "items": [{"product_name": "dudh", "quantity": 2, "unit": "litre"}],
            "amount": None, "language": "gu", "confidence": 0.95,
        }))
        self.assertIsInstance(parsed["items"][0]["quantity"], Decimal)
        self.assertIsNone(parsed["amount"])
        with self.assertRaises(Exception):
            validate_extraction(json.dumps({
                "customer_name": None, "transaction_type": "udhaar",
                "items": [{"product_name": "dudh", "quantity": 0, "unit": "litre"}],
                "amount": None, "language": "gu", "confidence": 0.95,
            }))

    def test_product_rate_calculation_is_deterministic_and_never_from_gemini(self):
        result = evaluate_extraction(self.extraction(
            items=[{"product_name": "dudh", "quantity": Decimal("2"), "unit": "litre"}],
            amount=None,
        ))
        self.assertEqual(result["status"], VoiceProposal.Status.DRAFT_READY)
        self.assertEqual(result["amount"], Decimal("72.00"))
        self.assertEqual(result["description"], "2 litre Milk @ 36.00")

    @patch("apps.voice.views.transcribe_and_extract")
    def test_voice_proposal_creates_draft_preview_but_does_not_post(self, gemini):
        gemini.return_value = ("Ramesh ne 200 udhar lakhjo", self.extraction())
        response = self.client.post(
            "/api/voice/proposals/",
            {"audio": SimpleUploadedFile("command.m4a", b"audio", content_type="audio/m4a")},
            format="multipart",
            HTTP_IDEMPOTENCY_KEY="voice-amount-01",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["status"], VoiceProposal.Status.DRAFT_READY)
        self.assertEqual(response.data["preview"]["projected_balance"], "200.00")
        self.assertEqual(response.data["draft"]["source"], "voice")
        self.assertEqual(LedgerEntry.objects.count(), 0)
        draft_id = response.data["draft"]["id"]

        confirmed = self.client.post(f"/api/transactions/{draft_id}/confirm/", {}, format="json")
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(LedgerEntry.objects.filter(status=LedgerEntry.Status.POSTED).count(), 1)

    @patch("apps.voice.views.transcribe_and_extract")
    def test_unknown_customer_requires_explicit_resolution_before_draft(self, gemini):
        gemini.return_value = ("Ramesh ne 200 udhar", self.extraction(customer_name="Rames"))
        response = self.client.post(
            "/api/voice/proposals/",
            {"audio": SimpleUploadedFile("command.m4a", b"audio", content_type="audio/m4a")},
            format="multipart",
            HTTP_IDEMPOTENCY_KEY="voice-unknown-01",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["status"], VoiceProposal.Status.NEEDS_CUSTOMER)
        self.assertIsNone(response.data["draft"])
        self.assertEqual(SimpleKhataEntry.objects.count(), 0)

        resolved = self.client.post(
            f"/api/voice/proposals/{response.data['id']}/customer/",
            {"customer_id": self.customer.pk},
            format="json",
        )
        self.assertEqual(resolved.status_code, 200)
        self.assertEqual(resolved.data["status"], VoiceProposal.Status.DRAFT_READY)
        self.assertEqual(SimpleKhataEntry.objects.count(), 1)
        self.assertEqual(LedgerEntry.objects.count(), 0)

    @patch("apps.voice.views.transcribe_and_extract")
    def test_spoken_customer_mismatch_requires_clarification_even_when_customer_selected(self, gemini):
        other_customer = Customer.objects.create(name="Mohan Shah", mobile_number="9876543211")
        gemini.return_value = ("Mohan ne 200 udhar", self.extraction(customer_name="Mohan Shah"))
        response = self.client.post(
            "/api/voice/proposals/",
            {
                "audio": SimpleUploadedFile("command.m4a", b"audio", content_type="audio/m4a"),
                "customer_id": str(self.customer.pk),
            },
            format="multipart",
            HTTP_IDEMPOTENCY_KEY="voice-selected-mismatch-01",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["status"], VoiceProposal.Status.NEEDS_CUSTOMER)
        self.assertIsNone(response.data["draft"])
        self.assertEqual(
            {item["id"] for item in response.data["customer_candidates"]},
            {self.customer.pk, other_customer.pk},
        )
        self.assertEqual(SimpleKhataEntry.objects.count(), 0)

    @patch("apps.voice.views.transcribe_and_extract")
    def test_same_idempotency_key_returns_existing_proposal_and_different_audio_conflicts(self, gemini):
        gemini.return_value = ("Ramesh 200 jama", self.extraction(transaction_type="jama"))
        first = self.client.post(
            "/api/voice/proposals/",
            {"audio": SimpleUploadedFile("command.m4a", b"same audio", content_type="audio/m4a")},
            format="multipart", HTTP_IDEMPOTENCY_KEY="voice-idem-01",
        )
        again = self.client.post(
            "/api/voice/proposals/",
            {"audio": SimpleUploadedFile("command.m4a", b"same audio", content_type="audio/m4a")},
            format="multipart", HTTP_IDEMPOTENCY_KEY="voice-idem-01",
        )
        self.assertEqual(first.data["id"], again.data["id"])
        self.assertEqual(gemini.call_count, 1)
        conflict = self.client.post(
            "/api/voice/proposals/",
            {"audio": SimpleUploadedFile("command.m4a", b"different", content_type="audio/m4a")},
            format="multipart", HTTP_IDEMPOTENCY_KEY="voice-idem-01",
        )
        self.assertEqual(conflict.status_code, 409)

    def test_searchable_business_rules_are_available_to_authenticated_users(self):
        BusinessKnowledge.objects.create(
            category=BusinessKnowledge.Category.TRANSACTION_RULE,
            title="Only confirmed drafts post",
            content="Voice entries must be confirmed by a user.",
            keywords=["voice", "confirm"],
        )
        response = self.client.get("/api/voice/knowledge/?search=confirmed")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data[0]["title"], "Only confirmed drafts post")

    def test_voice_endpoints_require_authentication(self):
        self.client.force_authenticate(user=None)
        response = self.client.get("/api/voice/knowledge/")
        self.assertEqual(response.status_code, 401)

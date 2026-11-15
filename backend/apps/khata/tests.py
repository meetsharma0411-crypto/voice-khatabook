from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.test import TestCase
from rest_framework.test import APIClient

from apps.catalog.models import Product, ProductPrice
from apps.customers.models import Customer

from .models import KhataTransaction, LedgerEntry, SimpleKhataEntry
from .services import (
    IdempotencyConflict,
    cancel_simple_entry,
    confirm_simple_entry,
    create_simple_entry,
    get_customer_balance,
    reverse_ledger_entry,
)


class SimpleKhataEntryServiceTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username="operator", password="test-pass")
        self.customer = Customer.objects.create(name="Ravi Patel", mobile_number="9876543210")

    def create_draft(self, *, kind="udhaar", amount="200.00", key="request-1"):
        return create_simple_entry(
            customer=self.customer,
            transaction_type=kind,
            amount=Decimal(amount),
            description="Test entry",
            transaction_date=date(2026, 11, 14),
            idempotency_key=key,
            created_by=self.user,
        )

    def test_draft_does_not_change_balance_and_udhaar_confirmation_posts_once(self):
        entry, created = self.create_draft()
        self.assertTrue(created)
        self.assertEqual(entry.status, SimpleKhataEntry.Status.DRAFT)
        self.assertEqual(get_customer_balance(self.customer.pk), Decimal("0.00"))

        posted, balance, first_confirmation = confirm_simple_entry(entry_id=entry.pk, actor=self.user)
        posted_again, same_balance, second_confirmation = confirm_simple_entry(
            entry_id=entry.pk, actor=self.user
        )

        self.assertTrue(first_confirmation)
        self.assertFalse(second_confirmation)
        self.assertEqual(posted.pk, posted_again.pk)
        self.assertEqual(balance, Decimal("200.00"))
        self.assertEqual(same_balance, balance)
        self.assertEqual(LedgerEntry.objects.filter(customer=self.customer).count(), 1)
        ledger_row = posted.ledger_entry
        self.assertEqual(ledger_row.entry_type, LedgerEntry.EntryType.UDHAAR)
        self.assertEqual(ledger_row.debit_amount, Decimal("200.00"))
        self.assertEqual(ledger_row.credit_amount, Decimal("0.00"))

    def test_jama_decreases_balance(self):
        opening = LedgerEntry.objects.create(
            customer=self.customer,
            entry_type=LedgerEntry.EntryType.OPENING_BALANCE,
            status=LedgerEntry.Status.POSTED,
            debit_amount=Decimal("500.00"),
        )
        entry, _ = self.create_draft(kind="jama", amount="100.00", key="jama-1")
        posted, balance, _ = confirm_simple_entry(entry_id=entry.pk, actor=self.user)
        self.assertEqual(balance, Decimal("400.00"))
        self.assertEqual(posted.ledger_entry.entry_type, LedgerEntry.EntryType.JAMA)
        self.assertEqual(posted.ledger_entry.credit_amount, Decimal("100.00"))
        opening.refresh_from_db()
        self.assertEqual(opening.debit_amount, Decimal("500.00"))
        self.assertEqual(opening.credit_amount, Decimal("0.00"))

    def test_idempotency_same_payload_returns_existing_and_changed_payload_conflicts(self):
        first, created = self.create_draft()
        retry, retry_created = self.create_draft()
        self.assertTrue(created)
        self.assertFalse(retry_created)
        self.assertEqual(first.pk, retry.pk)

        with self.assertRaises(IdempotencyConflict):
            self.create_draft(amount="201.00")

    def test_inactive_customer_cannot_receive_entry(self):
        self.customer.is_active = False
        self.customer.save(update_fields=("is_active", "updated_at"))
        with self.assertRaises(DjangoValidationError):
            self.create_draft()

    def test_cancel_draft_is_idempotent_and_does_not_change_balance(self):
        entry, _ = self.create_draft()
        cancelled, changed = cancel_simple_entry(entry_id=entry.pk)
        again, changed_again = cancel_simple_entry(entry_id=entry.pk)

        self.assertTrue(changed)
        self.assertFalse(changed_again)
        self.assertEqual(cancelled.pk, again.pk)
        self.assertEqual(again.status, SimpleKhataEntry.Status.CANCELLED)
        self.assertEqual(get_customer_balance(self.customer.pk), Decimal("0.00"))
        self.assertEqual(LedgerEntry.objects.filter(customer=self.customer).count(), 0)
        with self.assertRaises(DjangoValidationError):
            confirm_simple_entry(entry_id=entry.pk, actor=self.user)

    def test_reversal_is_linked_opposite_and_original_is_unchanged(self):
        entry, _ = self.create_draft()
        posted, _, _ = confirm_simple_entry(entry_id=entry.pk, actor=self.user)
        original = posted.ledger_entry
        original_amount = original.debit_amount

        reversal, balance = reverse_ledger_entry(
            ledger_entry_id=original.pk, reason="Wrong customer", actor=self.user
        )

        original.refresh_from_db()
        self.assertEqual(original.debit_amount, original_amount)
        self.assertEqual(reversal.reversal_of_id, original.pk)
        self.assertEqual(reversal.debit_amount, Decimal("0.00"))
        self.assertEqual(reversal.credit_amount, Decimal("200.00"))
        self.assertEqual(balance, Decimal("0.00"))
        self.assertEqual(LedgerEntry.objects.filter(reversal_of=original).count(), 1)
        with self.assertRaises(DjangoValidationError):
            reverse_ledger_entry(ledger_entry_id=original.pk, reason="Second reversal", actor=self.user)

    def test_posted_entry_cannot_be_edited_or_deleted(self):
        entry, _ = self.create_draft()
        posted, _, _ = confirm_simple_entry(entry_id=entry.pk, actor=self.user)
        posted.amount = Decimal("500.00")
        with self.assertRaises(DjangoValidationError):
            posted.save()
        with self.assertRaises(DjangoValidationError):
            posted.delete()


class KhataApiTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username="api-operator", password="test-pass")
        self.customer = Customer.objects.create(name="Ravi Patel", mobile_number="9876543210")
        self.client = APIClient()

    def authenticated(self):
        self.client.force_authenticate(self.user)

    def test_authentication_is_required(self):
        response = self.client.get("/api/customers/")
        self.assertIn(response.status_code, (401, 403))

    def test_cancel_draft_api_does_not_post_a_ledger_row(self):
        self.authenticated()
        response = self.client.post(
            "/api/transactions/",
            {
                "customer": self.customer.pk,
                "transaction_type": "udhaar",
                "amount": "55.00",
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY="cancel-api-draft",
        )
        self.assertEqual(response.status_code, 201)
        entry_id = response.data["id"]
        cancelled = self.client.post(f"/api/transactions/{entry_id}/cancel/", {}, format="json")
        self.assertEqual(cancelled.status_code, 200)
        self.assertEqual(cancelled.data["status"], SimpleKhataEntry.Status.CANCELLED)
        repeated = self.client.post(f"/api/transactions/{entry_id}/cancel/", {}, format="json")
        self.assertEqual(repeated.status_code, 200)
        self.assertEqual(LedgerEntry.objects.filter(customer=self.customer).count(), 0)

    def test_voice_source_stays_draft_until_explicit_confirmation(self):
        self.authenticated()
        draft = self.client.post(
            "/api/transactions/",
            {
                "customer": self.customer.pk,
                "transaction_type": "jama",
                "amount": "25.00",
                "source": "voice",
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY="voice-draft-key",
        )
        self.assertEqual(draft.status_code, 201)
        self.assertEqual(draft.data["source"], SimpleKhataEntry.Source.VOICE)
        self.assertEqual(draft.data["status"], SimpleKhataEntry.Status.DRAFT)
        self.assertEqual(draft.data["balance_effect"], "0.00")
        self.assertEqual(LedgerEntry.objects.filter(customer=self.customer).count(), 0)
        self.assertEqual(get_customer_balance(self.customer.pk), Decimal("0.00"))

        confirmed = self.client.post(
            f"/api/transactions/{draft.data['id']}/confirm/", {}, format="json"
        )
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(confirmed.data["status"], SimpleKhataEntry.Status.POSTED)
        self.assertEqual(confirmed.data["balance_after"], "-25.00")
        self.assertEqual(LedgerEntry.objects.filter(customer=self.customer).count(), 1)

    def test_generic_reversal_api_exposes_linked_details_and_is_one_time(self):
        self.authenticated()
        original = LedgerEntry.objects.create(
            customer=self.customer,
            entry_type=LedgerEntry.EntryType.OPENING_BALANCE,
            status=LedgerEntry.Status.POSTED,
            debit_amount=Decimal("75.00"),
            notes="Original opening balance",
            created_by=self.user,
        )
        response = self.client.post(
            f"/api/khata/ledger/{original.pk}/reverse/",
            {"reason": "Opening balance entered incorrectly"},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        reversal = LedgerEntry.objects.get(pk=response.data["reversal_ledger_entry"])
        self.assertEqual(reversal.reversal_of_id, original.pk)
        self.assertEqual(reversal.credit_amount, Decimal("75.00"))
        self.assertEqual(Decimal(response.data["balance_after"]), Decimal("0.00"))
        self.assertEqual(response.data["reversal"]["notes"], "Opening balance entered incorrectly")

        history = self.client.get(f"/api/customers/{self.customer.pk}/transactions/")
        original_row = next(row for row in history.data if row["id"] == original.pk)
        self.assertTrue(original_row["is_reversed"])
        self.assertEqual(original_row["reversal_entry_id"], reversal.pk)
        self.assertEqual(original_row["reversal"]["id"], reversal.pk)
        legacy_history = self.client.get(f"/api/khata/customers/{self.customer.pk}/ledger/")
        legacy_original = next(row for row in legacy_history.data if row["id"] == original.pk)
        self.assertTrue(legacy_original["is_reversed"])
        self.assertEqual(legacy_original["reversal"]["id"], reversal.pk)

        repeated = self.client.post(
            f"/api/khata/ledger/{original.pk}/reverse/",
            {"reason": "A second reversal"},
            format="json",
        )
        self.assertEqual(repeated.status_code, 400)
        reverse_a_reversal = self.client.post(
            f"/api/khata/ledger/{reversal.pk}/reverse/",
            {"reason": "Do not reverse reversal rows"},
            format="json",
        )
        self.assertEqual(reverse_a_reversal.status_code, 400)

    def test_simple_transaction_detail_shows_reversal_status(self):
        self.authenticated()
        created = self.client.post(
            "/api/transactions/",
            {
                "customer": self.customer.pk,
                "transaction_type": "udhaar",
                "amount": "40.00",
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY="reverse-detail-key",
        )
        entry_id = created.data["id"]
        self.client.post(f"/api/transactions/{entry_id}/confirm/", {}, format="json")
        reversed_response = self.client.post(
            f"/api/transactions/{entry_id}/reverse/",
            {"reason": "Wrong entry"},
            format="json",
        )
        self.assertEqual(reversed_response.status_code, 201)
        detail = self.client.get(f"/api/transactions/{entry_id}/")
        self.assertTrue(detail.data["is_reversed"])
        self.assertEqual(detail.data["net_balance_effect"], "0.00")
        self.assertEqual(detail.data["reversal"]["id"], reversed_response.data["reversal_ledger_entry"])

    def test_transaction_list_filters_by_status(self):
        self.authenticated()
        common = {
            "customer": self.customer.pk,
            "transaction_type": "udhaar",
            "amount": "10.00",
        }
        draft = self.client.post(
            "/api/transactions/", common, format="json", HTTP_IDEMPOTENCY_KEY="filter-draft"
        )
        cancelled = self.client.post(
            "/api/transactions/",
            {**common, "amount": "11.00"},
            format="json",
            HTTP_IDEMPOTENCY_KEY="filter-cancelled",
        )
        posted = self.client.post(
            "/api/transactions/",
            {**common, "amount": "12.00"},
            format="json",
            HTTP_IDEMPOTENCY_KEY="filter-posted",
        )
        self.client.post(f"/api/transactions/{cancelled.data['id']}/cancel/", {}, format="json")
        self.client.post(f"/api/transactions/{posted.data['id']}/confirm/", {}, format="json")

        draft_rows = self.client.get("/api/transactions/?status=draft").data
        cancelled_rows = self.client.get("/api/transactions/?status=cancelled").data
        posted_rows = self.client.get("/api/transactions/?status=posted").data
        self.assertEqual([row["id"] for row in draft_rows], [draft.data["id"]])
        self.assertEqual([row["id"] for row in cancelled_rows], [cancelled.data["id"]])
        self.assertEqual([row["id"] for row in posted_rows], [posted.data["id"]])

        invalid = self.client.get("/api/transactions/?status=unknown")
        self.assertEqual(invalid.status_code, 400)

    def test_create_idempotency_confirmation_and_history_apis(self):
        self.authenticated()
        payload = {
            "customer": self.customer.pk,
            "transaction_type": "udhaar",
            "amount": "200.00",
            "description": "Milk supplied",
            "transaction_date": "2026-11-14",
        }
        response = self.client.post(
            "/api/transactions/", payload, format="json", HTTP_IDEMPOTENCY_KEY="api-key-1"
        )
        self.assertEqual(response.status_code, 201)
        entry_id = response.data["id"]
        self.assertEqual(response.data["status"], "draft")
        self.assertEqual(response.data["balance_effect"], "0.00")

        same_request = self.client.post(
            "/api/transactions/", payload, format="json", HTTP_IDEMPOTENCY_KEY="api-key-1"
        )
        self.assertEqual(same_request.status_code, 200)
        conflict = self.client.post(
            "/api/transactions/",
            {**payload, "amount": "201.00"},
            format="json",
            HTTP_IDEMPOTENCY_KEY="api-key-1",
        )
        self.assertEqual(conflict.status_code, 409)

        confirmed = self.client.post(f"/api/transactions/{entry_id}/confirm/", {}, format="json")
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(confirmed.data["balance_after"], "200.00")
        balance = self.client.get(f"/api/customers/{self.customer.pk}/balance/")
        self.assertEqual(balance.status_code, 200)
        self.assertEqual(balance.data["balance"], "200.00")
        history = self.client.get(f"/api/customers/{self.customer.pk}/transactions/")
        self.assertEqual(history.status_code, 200)
        self.assertEqual(len(history.data), 1)

    def test_invalid_amount_inactive_customer_and_customer_search(self):
        self.authenticated()
        headers = {"HTTP_IDEMPOTENCY_KEY": "invalid-amount"}
        payload = {
            "customer": self.customer.pk,
            "transaction_type": "jama",
            "amount": "0.00",
        }
        invalid = self.client.post("/api/transactions/", payload, format="json", **headers)
        self.assertEqual(invalid.status_code, 400)

        search = self.client.get("/api/customers/search/?search=9876543210")
        self.assertEqual(search.status_code, 200)
        self.assertEqual(len(search.data), 1)

        self.customer.is_active = False
        self.customer.save(update_fields=("is_active", "updated_at"))
        inactive = self.client.post(
            "/api/transactions/",
            {**payload, "amount": "20.00"},
            format="json",
            HTTP_IDEMPOTENCY_KEY="inactive-customer",
        )
        self.assertEqual(inactive.status_code, 400)

    def test_dashboard_and_summary_use_posted_ledger_totals(self):
        self.authenticated()
        draft, _ = create_simple_entry(
            customer=self.customer,
            transaction_type=SimpleKhataEntry.TransactionType.UDHAAR,
            amount=Decimal("90.00"),
            description="Not posted yet",
            transaction_date=date(2026, 11, 14),
            idempotency_key="dashboard-draft",
            created_by=self.user,
        )
        self.assertEqual(draft.status, SimpleKhataEntry.Status.DRAFT)
        dashboard = self.client.get("/api/dashboard/")
        summary = self.client.get("/api/reports/summary/")
        self.assertEqual(dashboard.status_code, 200)
        self.assertEqual(summary.status_code, 200)
        self.assertEqual(dashboard.data["total_customers"], 1)
        self.assertEqual(dashboard.data["total_outstanding_balance"], "0.00")
        self.assertEqual(dashboard.data["recent_transactions"], [])

    def test_dashboard_recent_transactions_include_only_posted_entries_newest_first(self):
        self.authenticated()
        older = LedgerEntry.objects.create(
            customer=self.customer,
            entry_type=LedgerEntry.EntryType.UDHAAR,
            status=LedgerEntry.Status.POSTED,
            transaction_date=date(2026, 11, 10),
            debit_amount=Decimal("35.00"),
        )
        newer = LedgerEntry.objects.create(
            customer=self.customer,
            entry_type=LedgerEntry.EntryType.JAMA,
            status=LedgerEntry.Status.POSTED,
            transaction_date=date(2026, 11, 12),
            credit_amount=Decimal("10.00"),
        )
        create_simple_entry(
            customer=self.customer,
            transaction_type=SimpleKhataEntry.TransactionType.UDHAAR,
            amount=Decimal("90.00"),
            description="Still a draft",
            transaction_date=date(2026, 11, 14),
            idempotency_key="recent-draft",
            created_by=self.user,
        )

        response = self.client.get("/api/dashboard/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [row["id"] for row in response.data["recent_transactions"]],
            [newer.pk, older.pk],
        )
        self.assertEqual(response.data["recent_transactions"][0]["entry_type"], "jama")

    def test_customer_list_and_balance_return_server_calculated_activity_totals(self):
        self.authenticated()
        LedgerEntry.objects.create(
            customer=self.customer,
            entry_type=LedgerEntry.EntryType.OPENING_BALANCE,
            status=LedgerEntry.Status.POSTED,
            debit_amount=Decimal("500.00"),
        )
        for kind, amount, key in (
            (SimpleKhataEntry.TransactionType.UDHAAR, "200.00", "customer-summary-u"),
            (SimpleKhataEntry.TransactionType.JAMA, "100.00", "customer-summary-j"),
        ):
            draft, _ = create_simple_entry(
                customer=self.customer,
                transaction_type=kind,
                amount=Decimal(amount),
                description="Summary test",
                transaction_date=date(2026, 11, 14),
                idempotency_key=key,
                created_by=self.user,
            )
            confirm_simple_entry(entry_id=draft.pk, actor=self.user)

        customers = self.client.get("/api/customers/")
        customer = self.client.get(f"/api/customers/{self.customer.pk}/")
        balance = self.client.get(f"/api/customers/{self.customer.pk}/balance/")

        self.assertEqual(customers.status_code, 200)
        self.assertEqual(customers.data[0]["current_balance"], "600.00")
        self.assertEqual(customer.data["current_balance"], "600.00")
        self.assertEqual(Decimal(balance.data["balance"]), Decimal("600.00"))
        self.assertEqual(Decimal(balance.data["total_udhaar"]), Decimal("200.00"))
        self.assertEqual(Decimal(balance.data["total_jama"]), Decimal("100.00"))

    def test_draft_preview_projects_balance_without_posting(self):
        self.authenticated()
        LedgerEntry.objects.create(
            customer=self.customer,
            entry_type=LedgerEntry.EntryType.OPENING_BALANCE,
            status=LedgerEntry.Status.POSTED,
            debit_amount=Decimal("500.00"),
        )
        draft = self.client.post(
            "/api/transactions/",
            {
                "customer": self.customer.pk,
                "transaction_type": "udhaar",
                "amount": "200.00",
                "description": "Preview only",
                "transaction_date": "2026-11-14",
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY="preview-udhaar",
        )
        self.assertEqual(draft.status_code, 201)

        preview = self.client.get(f"/api/transactions/{draft.data['id']}/preview/")

        self.assertEqual(preview.status_code, 200)
        self.assertEqual(preview.data["previous_balance"], "500.00")
        self.assertEqual(preview.data["projected_balance"], "700.00")
        self.assertEqual(
            LedgerEntry.objects.filter(customer=self.customer).count(),
            1,
        )

    def test_existing_product_sale_draft_and_price_calculation_still_work(self):
        self.authenticated()
        product = Product.objects.create(name="Milk", default_unit="litre")
        ProductPrice.objects.create(
            product=product, price=Decimal("70.00"), effective_from=date(2026, 1, 1)
        )
        response = self.client.post(
            "/api/khata/transactions/",
            {
                "customer": self.customer.pk,
                "transaction_date": "2026-11-14",
                "items": [{"product": product.pk, "quantity": "2.000"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["total_amount"], "140.00")
        sale_id = response.data["id"]
        self.assertEqual(response.data["status"], KhataTransaction.Status.DRAFT)
        confirmed = self.client.post(f"/api/khata/transactions/{sale_id}/confirm/", {}, format="json")
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(confirmed.data["status"], KhataTransaction.Status.POSTED)
        self.assertIsNotNone(confirmed.data["ledger_entry_id"])
        reversed_sale = self.client.post(
            f"/api/khata/ledger/{confirmed.data['ledger_entry_id']}/reverse/",
            {"reason": "Sale entered against the wrong customer"},
            format="json",
        )
        self.assertEqual(reversed_sale.status_code, 201)
        sale_detail = self.client.get(f"/api/khata/transactions/{sale_id}/")
        self.assertTrue(sale_detail.data["is_reversed"])
        self.assertEqual(sale_detail.data["net_balance_effect"], "0.00")
        self.assertEqual(sale_detail.data["reversal"]["id"], reversed_sale.data["reversal_ledger_entry"])

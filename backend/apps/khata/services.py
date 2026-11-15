"""Atomic business operations for simple customer Udhaar/Jama entries."""
from decimal import Decimal

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.db.models import Q, Sum
from django.utils import timezone

from apps.customers.models import Customer

from .models import LedgerEntry, SimpleKhataEntry


class IdempotencyConflict(Exception):
    """The caller reused an idempotency key for a different request payload."""


def _same_payload(entry, *, customer, transaction_type, amount, description, transaction_date, source):
    return (
        entry.customer_id == customer.pk
        and entry.transaction_type == transaction_type
        and entry.amount == amount
        and entry.description == description
        and entry.transaction_date == transaction_date
        and entry.source == source
    )


def create_simple_entry(
    *, customer, transaction_type, amount, description, transaction_date,
    idempotency_key, created_by=None, source=SimpleKhataEntry.Source.MANUAL,
):
    """Create a draft, or return the matching draft/posted entry on a safe retry."""
    idempotency_key = idempotency_key.strip()
    if not idempotency_key:
        raise DjangoValidationError({"idempotency_key": "This value cannot be blank."})
    if not customer.is_active:
        raise DjangoValidationError({"customer": "Inactive customers cannot receive new entries."})

    existing = SimpleKhataEntry.objects.filter(idempotency_key=idempotency_key).first()
    if existing:
        if not _same_payload(
            existing, customer=customer, transaction_type=transaction_type,
            amount=amount, description=description,
            transaction_date=transaction_date, source=source,
        ):
            raise IdempotencyConflict
        return existing, False

    try:
        with transaction.atomic():
            entry = SimpleKhataEntry.objects.create(
                customer=customer,
                transaction_type=transaction_type,
                amount=amount,
                description=description,
                transaction_date=transaction_date,
                idempotency_key=idempotency_key,
                created_by=created_by,
                source=source,
            )
        return entry, True
    except (IntegrityError, DjangoValidationError):
        # A concurrent request may have won the unique-key race. Re-read after
        # the failed atomic block and only treat it as a retry if payloads match.
        existing = SimpleKhataEntry.objects.filter(idempotency_key=idempotency_key).first()
        if existing is None:
            raise
        if not _same_payload(
            existing, customer=customer, transaction_type=transaction_type,
            amount=amount, description=description,
            transaction_date=transaction_date, source=source,
        ):
            raise IdempotencyConflict
        return existing, False


def get_customer_balance(customer_id):
    totals = LedgerEntry.objects.filter(
        customer_id=customer_id, status=LedgerEntry.Status.POSTED
    ).aggregate(debits=Sum("debit_amount"), credits=Sum("credit_amount"))
    return (totals["debits"] or Decimal("0.00")) - (totals["credits"] or Decimal("0.00"))


def get_customer_activity_totals(customer_id):
    """Return posted Udhaar/Jama totals using the same reversal rules as reports."""
    posted = LedgerEntry.objects.filter(
        customer_id=customer_id, status=LedgerEntry.Status.POSTED
    )
    totals = posted.aggregate(
        udhaar=Sum(
            "debit_amount",
            filter=Q(entry_type__in=(LedgerEntry.EntryType.UDHAAR, LedgerEntry.EntryType.SALE)),
        ),
        udhaar_reversed=Sum(
            "credit_amount",
            filter=Q(
                entry_type=LedgerEntry.EntryType.REVERSAL,
                reversal_of__entry_type__in=(LedgerEntry.EntryType.UDHAAR, LedgerEntry.EntryType.SALE),
            ),
        ),
        jama=Sum(
            "credit_amount",
            filter=Q(entry_type__in=(LedgerEntry.EntryType.JAMA, LedgerEntry.EntryType.PAYMENT)),
        ),
        jama_reversed=Sum(
            "debit_amount",
            filter=Q(
                entry_type=LedgerEntry.EntryType.REVERSAL,
                reversal_of__entry_type__in=(LedgerEntry.EntryType.JAMA, LedgerEntry.EntryType.PAYMENT),
            ),
        ),
    )
    zero = Decimal("0.00")
    return {
        "total_udhaar": (totals["udhaar"] or zero) - (totals["udhaar_reversed"] or zero),
        "total_jama": (totals["jama"] or zero) - (totals["jama_reversed"] or zero),
    }


def preview_simple_entry(*, entry_id):
    """Calculate a draft projection from posted ledger rows without posting it."""
    entry = SimpleKhataEntry.objects.select_related("customer").get(pk=entry_id)
    if entry.status != SimpleKhataEntry.Status.DRAFT:
        raise DjangoValidationError("Only a draft entry can be previewed.")
    previous_balance = get_customer_balance(entry.customer_id)
    signed_amount = (
        entry.amount
        if entry.transaction_type == SimpleKhataEntry.TransactionType.UDHAAR
        else -entry.amount
    )
    return entry, previous_balance, previous_balance + signed_amount


@transaction.atomic
def confirm_simple_entry(*, entry_id, actor=None):
    """Post a draft exactly once to the existing customer ledger."""
    entry = SimpleKhataEntry.objects.select_for_update().get(pk=entry_id)
    customer = Customer.objects.select_for_update().get(pk=entry.customer_id)

    if entry.status == SimpleKhataEntry.Status.POSTED:
        return entry, get_customer_balance(customer.pk), False
    if entry.status != SimpleKhataEntry.Status.DRAFT:
        raise DjangoValidationError("Only a draft entry can be confirmed.")
    if not customer.is_active:
        raise DjangoValidationError({"customer": "Inactive customers cannot receive new entries."})

    is_udhaar = entry.transaction_type == SimpleKhataEntry.TransactionType.UDHAAR
    ledger_entry = LedgerEntry.objects.create(
        customer=customer,
        entry_type=LedgerEntry.EntryType.UDHAAR if is_udhaar else LedgerEntry.EntryType.JAMA,
        status=LedgerEntry.Status.POSTED,
        transaction_date=entry.transaction_date,
        debit_amount=entry.amount if is_udhaar else Decimal("0.00"),
        credit_amount=Decimal("0.00") if is_udhaar else entry.amount,
        notes=entry.description,
        created_by=actor,
    )
    entry.status = SimpleKhataEntry.Status.POSTED
    entry.ledger_entry = ledger_entry
    entry.save(update_fields=("status", "ledger_entry", "updated_at"))
    return entry, get_customer_balance(customer.pk), True


@transaction.atomic
def cancel_simple_entry(*, entry_id):
    """Cancel a draft under a row lock without creating a ledger entry."""
    entry = SimpleKhataEntry.objects.select_for_update().get(pk=entry_id)
    if entry.status == SimpleKhataEntry.Status.CANCELLED:
        return entry, False
    if entry.status != SimpleKhataEntry.Status.DRAFT:
        raise DjangoValidationError("Only a draft entry can be cancelled.")
    entry.status = SimpleKhataEntry.Status.CANCELLED
    entry.save(update_fields=("status", "updated_at"))
    return entry, True


@transaction.atomic
def reverse_ledger_entry(*, ledger_entry_id, reason, actor=None):
    """Post one linked, opposite ledger row while preserving the original."""
    original = LedgerEntry.objects.select_for_update().get(pk=ledger_entry_id)
    Customer.objects.select_for_update().get(pk=original.customer_id)
    if original.status != LedgerEntry.Status.POSTED:
        raise DjangoValidationError("Only a posted ledger entry can be reversed.")
    if original.entry_type == LedgerEntry.EntryType.REVERSAL:
        raise DjangoValidationError("A reversal entry cannot itself be reversed.")
    if not reason or not reason.strip():
        raise DjangoValidationError({"reason": "Provide a reason for this correction."})
    if LedgerEntry.objects.filter(reversal_of=original).exists():
        raise DjangoValidationError("This ledger entry has already been reversed.")

    reversal = LedgerEntry.objects.create(
        customer_id=original.customer_id,
        reversal_of=original,
        entry_type=LedgerEntry.EntryType.REVERSAL,
        status=LedgerEntry.Status.POSTED,
        transaction_date=timezone.localdate(),
        debit_amount=original.credit_amount,
        credit_amount=original.debit_amount,
        notes=reason.strip(),
        created_by=actor,
    )
    return reversal, get_customer_balance(original.customer_id)

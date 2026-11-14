"""Append-only customer ledger entries."""
from decimal import Decimal, ROUND_HALF_UP

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class LedgerEntryQuerySet(models.QuerySet):
    def delete(self):
        if self.filter(status=LedgerEntry.Status.POSTED).exists():
            raise ValidationError("Posted ledger entries cannot be deleted; create a reversal instead.")
        return super().delete()


class LedgerEntry(models.Model):
    class EntryType(models.TextChoices):
        OPENING_BALANCE = "opening_balance", "Opening balance"
        SALE = "sale", "Sale"
        UDHAAR = "udhaar", "Udhaar"
        JAMA = "jama", "Jama"
        PAYMENT = "payment", "Payment"
        ADJUSTMENT = "adjustment", "Adjustment"
        REVERSAL = "reversal", "Reversal"

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        POSTED = "posted", "Posted"

    customer = models.ForeignKey(
        "customers.Customer",
        on_delete=models.PROTECT,
        related_name="ledger_entries",
    )
    reversal_of = models.OneToOneField(
        "self",
        on_delete=models.PROTECT,
        related_name="reversal_entry",
        null=True,
        blank=True,
    )
    entry_type = models.CharField(max_length=24, choices=EntryType.choices)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT)
    transaction_date = models.DateField(default=timezone.localdate, db_index=True)
    debit_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    credit_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_khata_entries",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    objects = LedgerEntryQuerySet.as_manager()

    class Meta:
        ordering = ["transaction_date", "created_at", "id"]
        indexes = [models.Index(fields=["customer", "transaction_date", "id"])]

    def __str__(self):
        return f"{self.get_entry_type_display()} for {self.customer} ({self.transaction_date})"

    def clean(self):
        super().clean()
        if self.debit_amount < 0 or self.credit_amount < 0:
            raise ValidationError("Ledger debit and credit amounts cannot be negative.")
        if (self.debit_amount > 0) == (self.credit_amount > 0):
            raise ValidationError("A ledger entry must have exactly one positive debit or credit amount.")
        if self.reversal_of_id:
            original = self.reversal_of
            if self.entry_type != self.EntryType.REVERSAL:
                raise ValidationError({"entry_type": "A linked reversal must use the reversal entry type."})
            if original.status != self.Status.POSTED:
                raise ValidationError({"reversal_of": "Only posted ledger entries can be reversed."})
            if original.customer_id != self.customer_id:
                raise ValidationError({"customer": "A reversal must belong to the original customer."})
            if self.debit_amount != original.credit_amount or self.credit_amount != original.debit_amount:
                raise ValidationError("A reversal must exactly swap the original debit and credit amounts.")
        elif self.entry_type == self.EntryType.REVERSAL:
            raise ValidationError({"reversal_of": "A reversal entry must link to its original entry."})

    def save(self, *args, **kwargs):
        if self.pk:
            previous = type(self).objects.filter(pk=self.pk).first()
            if previous and previous.status == self.Status.POSTED:
                protected_fields = (
                    "customer_id",
                    "entry_type",
                    "transaction_date",
                    "debit_amount",
                    "credit_amount",
                    "notes",
                    "created_by_id",
                    "reversal_of_id",
                )
                if any(getattr(previous, field) != getattr(self, field) for field in protected_fields):
                    raise ValidationError("Posted ledger entries are immutable; create a reversal or adjustment.")
                if self.status != previous.status:
                    raise ValidationError("Posted ledger entries cannot be unposted.")
        self.full_clean()
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        if self.status == self.Status.POSTED:
            raise ValidationError("Posted ledger entries cannot be deleted; create a reversal instead.")
        return super().delete(*args, **kwargs)


class KhataTransactionQuerySet(models.QuerySet):
    def delete(self):
        if self.filter(status=KhataTransaction.Status.POSTED).exists():
            raise ValidationError("Posted transactions cannot be deleted; create a reversal instead.")
        return super().delete()


class KhataTransaction(models.Model):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        POSTED = "posted", "Posted"
        CANCELLED = "cancelled", "Cancelled"

    class Source(models.TextChoices):
        MANUAL = "manual", "Manual"
        VOICE = "voice", "Voice"
        SYSTEM = "system", "System"

    customer = models.ForeignKey(
        "customers.Customer",
        on_delete=models.PROTECT,
        related_name="khata_transactions",
    )
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT)
    source = models.CharField(max_length=10, choices=Source.choices, default=Source.MANUAL)
    transaction_date = models.DateField(default=timezone.localdate, db_index=True)
    total_amount = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    notes = models.TextField(blank=True)
    ledger_entry = models.OneToOneField(
        LedgerEntry,
        on_delete=models.PROTECT,
        related_name="sale_transaction",
        null=True,
        blank=True,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_khata_transactions",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = KhataTransactionQuerySet.as_manager()

    class Meta:
        ordering = ["-transaction_date", "-created_at", "-id"]
        indexes = [models.Index(fields=["customer", "transaction_date", "status"])]

    def __str__(self):
        return f"Sale #{self.pk or 'new'} for {self.customer}"

    def clean(self):
        super().clean()
        if self.total_amount < 0:
            raise ValidationError({"total_amount": "Transaction total cannot be negative."})
        if self.status == self.Status.POSTED:
            if self.ledger_entry_id is None:
                raise ValidationError({"ledger_entry": "A posted sale must have a ledger entry."})
            if self.total_amount <= 0:
                raise ValidationError({"total_amount": "A posted sale must have a positive total."})

    def save(self, *args, **kwargs):
        if self.pk:
            previous = type(self).objects.filter(pk=self.pk).first()
            if previous and previous.status in (self.Status.POSTED, self.Status.CANCELLED):
                protected_fields = (
                    "customer_id",
                    "source",
                    "transaction_date",
                    "total_amount",
                    "notes",
                    "ledger_entry_id",
                    "created_by_id",
                )
                if any(getattr(previous, field) != getattr(self, field) for field in protected_fields):
                    raise ValidationError("Posted or cancelled transactions are immutable.")
                if self.status != previous.status:
                    raise ValidationError("Posted or cancelled transactions cannot be reopened.")
        self.full_clean()
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        if self.status == self.Status.POSTED:
            raise ValidationError("Posted transactions cannot be deleted; create a reversal instead.")
        return super().delete(*args, **kwargs)


class KhataTransactionItemQuerySet(models.QuerySet):
    def delete(self):
        if self.filter(transaction__status__in=(
            KhataTransaction.Status.POSTED,
            KhataTransaction.Status.CANCELLED,
        )).exists():
            raise ValidationError("Items in posted or cancelled transactions cannot be deleted.")
        return super().delete()


class KhataTransactionItem(models.Model):
    transaction = models.ForeignKey(
        KhataTransaction,
        on_delete=models.CASCADE,
        related_name="items",
    )
    product = models.ForeignKey(
        "catalog.Product",
        on_delete=models.PROTECT,
        related_name="transaction_items",
    )
    product_name = models.CharField(max_length=160)
    quantity = models.DecimalField(max_digits=12, decimal_places=3)
    unit = models.CharField(max_length=24)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    line_total = models.DecimalField(max_digits=14, decimal_places=2)

    objects = KhataTransactionItemQuerySet.as_manager()

    class Meta:
        ordering = ["id"]

    def clean(self):
        super().clean()
        if self.quantity <= 0:
            raise ValidationError({"quantity": "Quantity must be greater than zero."})
        if self.unit_price <= 0:
            raise ValidationError({"unit_price": "Unit price must be greater than zero."})
        if self.line_total != (self.quantity * self.unit_price).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        ):
            raise ValidationError({"line_total": "Line total must equal quantity multiplied by unit price."})

    def _ensure_parent_editable(self):
        parent = KhataTransaction.objects.get(pk=self.transaction_id)
        if parent.status != KhataTransaction.Status.DRAFT:
            raise ValidationError("Items can only be changed while the transaction is a draft.")

    def save(self, *args, **kwargs):
        self._ensure_parent_editable()
        self.full_clean()
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        self._ensure_parent_editable()
        return super().delete(*args, **kwargs)

    def __str__(self):
        return f"{self.product_name}: {self.quantity} {self.unit}"


class SimpleKhataEntryQuerySet(models.QuerySet):
    def delete(self):
        if self.filter(status=SimpleKhataEntry.Status.POSTED).exists():
            raise ValidationError("Posted entries cannot be deleted; create a reversal instead.")
        return super().delete()


class SimpleKhataEntry(models.Model):
    """A product-free Udhaar/Jama draft that posts into the shared ledger."""

    class TransactionType(models.TextChoices):
        UDHAAR = "udhaar", "Udhaar"
        JAMA = "jama", "Jama"

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        POSTED = "posted", "Posted"
        CANCELLED = "cancelled", "Cancelled"

    class Source(models.TextChoices):
        MANUAL = "manual", "Manual"
        VOICE = "voice", "Voice"

    customer = models.ForeignKey(
        "customers.Customer",
        on_delete=models.PROTECT,
        related_name="simple_khata_entries",
    )
    transaction_type = models.CharField(max_length=8, choices=TransactionType.choices)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    description = models.TextField(blank=True)
    transaction_date = models.DateField(default=timezone.localdate, db_index=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT)
    source = models.CharField(max_length=10, choices=Source.choices, default=Source.MANUAL)
    idempotency_key = models.CharField(max_length=128, unique=True)
    ledger_entry = models.OneToOneField(
        LedgerEntry,
        on_delete=models.PROTECT,
        related_name="simple_khata_entry",
        null=True,
        blank=True,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_simple_khata_entries",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = SimpleKhataEntryQuerySet.as_manager()

    class Meta:
        ordering = ["-transaction_date", "-created_at", "-id"]
        indexes = [models.Index(fields=["customer", "transaction_date", "status"])]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(amount__gt=0),
                name="khata_simple_entry_amount_positive",
            ),
        ]

    def __str__(self):
        return f"{self.get_transaction_type_display()} #{self.pk or 'new'} for {self.customer}"

    def clean(self):
        super().clean()
        if self.amount <= 0:
            raise ValidationError({"amount": "Amount must be greater than zero."})
        if self.status == self.Status.POSTED and self.ledger_entry_id is None:
            raise ValidationError({"ledger_entry": "A posted entry must link to a ledger row."})
        if self.status != self.Status.POSTED and self.ledger_entry_id is not None:
            raise ValidationError({"ledger_entry": "Only posted entries may link to a ledger row."})

    def save(self, *args, **kwargs):
        if self.pk:
            previous = type(self).objects.filter(pk=self.pk).first()
            if previous and previous.status in (self.Status.POSTED, self.Status.CANCELLED):
                protected_fields = (
                    "customer_id", "transaction_type", "amount", "description",
                    "transaction_date", "source", "idempotency_key", "ledger_entry_id",
                    "created_by_id",
                )
                if any(getattr(previous, field) != getattr(self, field) for field in protected_fields):
                    raise ValidationError("Posted or cancelled entries are immutable.")
                if self.status != previous.status:
                    raise ValidationError("Posted or cancelled entries cannot be reopened.")
        self.full_clean()
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        if self.status == self.Status.POSTED:
            raise ValidationError("Posted entries cannot be deleted; create a reversal instead.")
        return super().delete(*args, **kwargs)

"""Serializers for product-free Udhaar/Jama entries."""
from decimal import Decimal

from django.utils import timezone
from rest_framework import serializers

from apps.customers.models import Customer

from .models import LedgerEntry, SimpleKhataEntry


class SimpleKhataEntryCreateSerializer(serializers.Serializer):
    customer = serializers.PrimaryKeyRelatedField(queryset=Customer.objects.filter(is_active=True))
    transaction_type = serializers.ChoiceField(choices=SimpleKhataEntry.TransactionType.choices)
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal("0.01"))
    description = serializers.CharField(required=False, allow_blank=True, default="")
    transaction_date = serializers.DateField(required=False, default=timezone.localdate)
    source = serializers.ChoiceField(
        choices=SimpleKhataEntry.Source.choices,
        required=False,
        default=SimpleKhataEntry.Source.MANUAL,
    )


class SimpleKhataEntrySerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    ledger_entry_id = serializers.IntegerField(read_only=True, allow_null=True)
    balance_effect = serializers.SerializerMethodField()
    net_balance_effect = serializers.SerializerMethodField()
    is_reversed = serializers.SerializerMethodField()
    reversal = serializers.SerializerMethodField()

    class Meta:
        model = SimpleKhataEntry
        fields = (
            "id", "customer", "customer_name", "transaction_type", "amount",
            "description", "transaction_date", "status", "source",
            "idempotency_key", "ledger_entry_id", "balance_effect", "net_balance_effect",
            "is_reversed", "reversal", "created_at",
        )
        read_only_fields = fields

    def get_balance_effect(self, obj):
        if obj.status != SimpleKhataEntry.Status.POSTED:
            return "0.00"
        if obj.transaction_type == SimpleKhataEntry.TransactionType.UDHAAR:
            return str(obj.amount)
        return str(-obj.amount)

    def _get_reversal(self, obj):
        if not obj.ledger_entry_id:
            return None
        try:
            return obj.ledger_entry.reversal_entry
        except LedgerEntry.DoesNotExist:
            return None

    def get_is_reversed(self, obj):
        return self._get_reversal(obj) is not None

    def get_reversal(self, obj):
        reversal = self._get_reversal(obj)
        return LedgerReversalSerializer(reversal).data if reversal else None

    def get_net_balance_effect(self, obj):
        if self._get_reversal(obj):
            return "0.00"
        return self.get_balance_effect(obj)


class LedgerReversalSerializer(serializers.ModelSerializer):
    class Meta:
        model = LedgerEntry
        fields = (
            "id", "transaction_date", "debit_amount", "credit_amount",
            "notes", "created_by", "created_at",
        )
        read_only_fields = fields


class LedgerHistorySerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    reversal_of_id = serializers.IntegerField(read_only=True, allow_null=True)
    is_reversed = serializers.SerializerMethodField()
    reversal_entry_id = serializers.SerializerMethodField()
    reversal = serializers.SerializerMethodField()

    class Meta:
        model = LedgerEntry
        fields = (
            "id", "customer", "customer_name", "entry_type", "transaction_date",
            "debit_amount", "credit_amount", "notes", "reversal_of_id", "created_by",
            "created_at", "is_reversed", "reversal_entry_id", "reversal",
        )
        read_only_fields = fields

    def _get_reversal(self, obj):
        try:
            return obj.reversal_entry
        except LedgerEntry.DoesNotExist:
            return None

    def get_is_reversed(self, obj):
        return self._get_reversal(obj) is not None

    def get_reversal_entry_id(self, obj):
        reversal = self._get_reversal(obj)
        return reversal.pk if reversal else None

    def get_reversal(self, obj):
        reversal = self._get_reversal(obj)
        return LedgerReversalSerializer(reversal).data if reversal else None


class ReversalSerializer(serializers.Serializer):
    reason = serializers.CharField(trim_whitespace=True, allow_blank=False)

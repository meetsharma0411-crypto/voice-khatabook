from rest_framework import serializers

from .entry_serializers import LedgerReversalSerializer
from .models import LedgerEntry


class LedgerEntrySerializer(serializers.ModelSerializer):
    running_balance = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    is_reversed = serializers.SerializerMethodField()
    reversal_entry_id = serializers.SerializerMethodField()
    reversal = serializers.SerializerMethodField()

    class Meta:
        model = LedgerEntry
        fields = (
            "id",
            "transaction_date",
            "entry_type",
            "debit_amount",
            "credit_amount",
            "running_balance",
            "notes",
            "is_reversed",
            "reversal_entry_id",
            "reversal",
            "created_at",
        )

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

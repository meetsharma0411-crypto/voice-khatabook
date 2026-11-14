from rest_framework import serializers

from .models import LedgerEntry


class LedgerEntrySerializer(serializers.ModelSerializer):
    running_balance = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)

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
            "created_at",
        )

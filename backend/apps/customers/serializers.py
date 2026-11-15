from rest_framework import serializers
from django.db import transaction
from django.utils import timezone

from apps.khata.models import LedgerEntry
from apps.khata.services import get_customer_balance

from .models import Customer


class CustomerSerializer(serializers.ModelSerializer):
    current_balance = serializers.SerializerMethodField()
    opening_balance_amount = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        min_value=0,
        required=False,
        write_only=True,
    )
    opening_balance_side = serializers.ChoiceField(
        choices=(("debit", "Customer owes business"), ("credit", "Business owes customer")),
        required=False,
        write_only=True,
    )
    opening_balance_date = serializers.DateField(required=False, write_only=True)

    class Meta:
        model = Customer
        fields = (
            "id",
            "name",
            "mobile_number",
            "address",
            "notes",
            "is_active",
            "current_balance",
            "opening_balance_amount",
            "opening_balance_side",
            "opening_balance_date",
            "created_at",
            "updated_at",
        )
        read_only_fields = ("id", "created_at", "updated_at")

    def validate(self, attrs):
        amount = attrs.get("opening_balance_amount")
        side = attrs.get("opening_balance_side")
        balance_date = attrs.get("opening_balance_date")
        if self.instance is not None and (
            amount is not None or side is not None or balance_date is not None
        ):
            raise serializers.ValidationError(
                "Opening balance is recorded once at customer creation. Use a ledger adjustment to correct it."
            )
        if amount is not None and amount > 0 and side is None:
            raise serializers.ValidationError(
                {"opening_balance_side": "Choose debit or credit for a non-zero opening balance."}
            )
        if side is not None and (amount is None or amount == 0):
            raise serializers.ValidationError(
                {"opening_balance_amount": "Enter a positive amount when specifying an opening balance side."}
            )
        if balance_date is not None and (amount is None or amount == 0):
            raise serializers.ValidationError(
                {"opening_balance_amount": "Enter a positive amount when specifying an opening balance date."}
            )
        return attrs

    def get_current_balance(self, obj):
        balance = getattr(obj, "current_balance", None)
        if balance is None:
            balance = get_customer_balance(obj.pk)
        return f"{balance:.2f}"

    def create(self, validated_data):
        amount = validated_data.pop("opening_balance_amount", None)
        side = validated_data.pop("opening_balance_side", None)
        balance_date = validated_data.pop("opening_balance_date", None)
        with transaction.atomic():
            customer = super().create(validated_data)

            if amount is not None and amount > 0:
                request = self.context.get("request")
                actor = request.user if request and request.user.is_authenticated else None
                LedgerEntry.objects.create(
                    customer=customer,
                    entry_type=LedgerEntry.EntryType.OPENING_BALANCE,
                    status=LedgerEntry.Status.POSTED,
                    transaction_date=balance_date or timezone.localdate(),
                    debit_amount=amount if side == "debit" else 0,
                    credit_amount=amount if side == "credit" else 0,
                    notes="Opening balance at customer registration",
                    created_by=actor,
                )
        return customer

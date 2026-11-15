from decimal import Decimal, ROUND_HALF_UP

from django.db import transaction
from rest_framework import serializers

from apps.catalog.models import Product
from apps.customers.models import Customer

from .entry_serializers import LedgerReversalSerializer
from .models import KhataTransaction, KhataTransactionItem, LedgerEntry


class TransactionItemInputSerializer(serializers.Serializer):
    product = serializers.PrimaryKeyRelatedField(queryset=Product.objects.filter(is_active=True))
    quantity = serializers.DecimalField(max_digits=12, decimal_places=3, min_value=Decimal("0.001"))


class TransactionItemOutputSerializer(serializers.ModelSerializer):
    product_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = KhataTransactionItem
        fields = (
            "id",
            "product_id",
            "product_name",
            "quantity",
            "unit",
            "unit_price",
            "line_total",
        )


class KhataTransactionSerializer(serializers.ModelSerializer):
    customer = serializers.PrimaryKeyRelatedField(queryset=Customer.objects.filter(is_active=True))
    items = TransactionItemInputSerializer(many=True, write_only=True, required=True)
    line_items = TransactionItemOutputSerializer(many=True, source="items", read_only=True)
    ledger_entry_id = serializers.IntegerField(read_only=True, allow_null=True)
    is_reversed = serializers.SerializerMethodField()
    reversal = serializers.SerializerMethodField()
    net_balance_effect = serializers.SerializerMethodField()

    class Meta:
        model = KhataTransaction
        fields = (
            "id",
            "customer",
            "status",
            "source",
            "transaction_date",
            "items",
            "line_items",
            "total_amount",
            "ledger_entry_id",
            "is_reversed",
            "reversal",
            "net_balance_effect",
            "notes",
            "created_at",
            "updated_at",
        )
        read_only_fields = (
            "id",
            "status",
            "source",
            "total_amount",
            "ledger_entry_id",
            "is_reversed",
            "reversal",
            "net_balance_effect",
            "created_at",
            "updated_at",
        )

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
        if not obj.ledger_entry_id or self._get_reversal(obj):
            return "0.00"
        return str(obj.total_amount)

    def validate_items(self, items):
        if not items:
            raise serializers.ValidationError("Add at least one product to the transaction.")
        return items

    def create(self, validated_data):
        input_items = validated_data.pop("items")
        request = self.context.get("request")
        actor = request.user if request and request.user.is_authenticated else None
        with transaction.atomic():
            khata_transaction = KhataTransaction.objects.create(
                **validated_data,
                created_by=actor,
                source=KhataTransaction.Source.MANUAL,
            )
            total = Decimal("0.00")
            for row in input_items:
                product = row["product"]
                price_record = product.price_on(khata_transaction.transaction_date)
                if price_record is None:
                    raise serializers.ValidationError(
                        {"items": f"No price is set for {product.name} on {khata_transaction.transaction_date}."}
                    )
                quantity = row["quantity"]
                line_total = (quantity * price_record.price).quantize(
                    Decimal("0.01"), rounding=ROUND_HALF_UP
                )
                KhataTransactionItem.objects.create(
                    transaction=khata_transaction,
                    product=product,
                    product_name=product.name,
                    quantity=quantity,
                    unit=product.default_unit,
                    unit_price=price_record.price,
                    line_total=line_total,
                )
                total += line_total
            khata_transaction.total_amount = total
            khata_transaction.save(update_fields=("total_amount", "updated_at"))
        return khata_transaction

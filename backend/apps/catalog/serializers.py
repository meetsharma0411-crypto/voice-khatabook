from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from .models import Product, ProductPrice


class ProductPriceSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductPrice
        fields = ("id", "price", "effective_from", "created_at")
        read_only_fields = ("id", "created_at")


class ProductSerializer(serializers.ModelSerializer):
    current_price = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True, allow_null=True
    )
    prices = ProductPriceSerializer(many=True, read_only=True)

    class Meta:
        model = Product
        fields = (
            "id",
            "name",
            "default_unit",
            "is_active",
            "current_price",
            "prices",
            "created_at",
            "updated_at",
        )
        read_only_fields = ("id", "created_at", "updated_at")


class ProductPriceCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductPrice
        fields = ("price", "effective_from")

    def validate_price(self, value):
        if value <= 0:
            raise serializers.ValidationError("Price must be greater than zero.")
        return value

    def validate(self, attrs):
        effective_from = attrs.get("effective_from", timezone.localdate())
        product = self.context["product"]
        if ProductPrice.objects.filter(product=product, effective_from=effective_from).exists():
            raise serializers.ValidationError(
                {"effective_from": "A price already exists for this product on that date."}
            )
        attrs["effective_from"] = effective_from
        return attrs

    def create(self, validated_data):
        product = self.context["product"]
        with transaction.atomic():
            return ProductPrice.objects.create(product=product, **validated_data)

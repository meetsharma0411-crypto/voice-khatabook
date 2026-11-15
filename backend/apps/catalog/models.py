"""Products and effective-dated prices."""
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class Product(models.Model):
    name = models.CharField(max_length=160)
    default_unit = models.CharField(max_length=24, default="piece")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name", "id"]

    def __str__(self):
        return self.name

    def price_on(self, effective_date=None):
        effective_date = effective_date or timezone.localdate()
        return self.prices.filter(effective_from__lte=effective_date).order_by("-effective_from", "-id").first()

    @property
    def current_price(self):
        price = self.price_on()
        return price.price if price else None


class ProductPrice(models.Model):
    product = models.ForeignKey(Product, on_delete=models.PROTECT, related_name="prices")
    price = models.DecimalField(max_digits=12, decimal_places=2)
    effective_from = models.DateField(default=timezone.localdate)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-effective_from", "-id"]
        constraints = [
            models.UniqueConstraint(fields=["product", "effective_from"], name="unique_product_price_date")
        ]

    def clean(self):
        super().clean()
        if self.price <= 0:
            raise ValidationError({"price": "Product price must be greater than zero."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.product}: {self.price} from {self.effective_from}"


class ProductAlias(models.Model):
    """A spoken, translated, or commonly typed name for a catalog product."""

    class Language(models.TextChoices):
        GUJARATI = "gu", "Gujarati"
        HINDI = "hi", "Hindi"
        ENGLISH = "en", "English"
        HINGLISH = "hinglish", "Hinglish"
        MIXED = "mixed", "Mixed"

    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="aliases")
    alias = models.CharField(max_length=160, unique=True)
    language = models.CharField(max_length=12, choices=Language.choices, default=Language.ENGLISH)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["alias", "id"]

    def __str__(self):
        return f"{self.alias} → {self.product.name}"

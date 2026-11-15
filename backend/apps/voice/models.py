"""Voice proposal and searchable business knowledge records."""

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class BusinessKnowledge(models.Model):
    """Small, searchable business rules used to ground voice extraction."""

    class Category(models.TextChoices):
        TRANSACTION_RULE = "transaction_rule", "Transaction rule"
        PRODUCT_GUIDANCE = "product_guidance", "Product guidance"

    category = models.CharField(max_length=24, choices=Category.choices)
    title = models.CharField(max_length=180)
    content = models.TextField()
    keywords = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["category", "title", "id"]

    def __str__(self):
        return self.title


class VoiceProposal(models.Model):
    """An auditable voice interpretation; audio itself is never stored here."""

    class Status(models.TextChoices):
        PROCESSING = "processing", "Processing"
        NEEDS_CUSTOMER = "needs_customer", "Needs customer clarification"
        NEEDS_CLARIFICATION = "needs_clarification", "Needs clarification"
        DRAFT_READY = "draft_ready", "Draft ready for confirmation"
        FAILED = "failed", "Failed"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="voice_proposals")
    idempotency_key = models.CharField(max_length=128, unique=True)
    audio_sha256 = models.CharField(max_length=64)
    requested_customer = models.ForeignKey(
        "customers.Customer", null=True, blank=True, on_delete=models.PROTECT,
        related_name="requested_voice_proposals",
    )
    customer = models.ForeignKey(
        "customers.Customer", null=True, blank=True, on_delete=models.PROTECT,
        related_name="voice_proposals",
    )
    simple_entry = models.ForeignKey(
        "khata.SimpleKhataEntry", null=True, blank=True, on_delete=models.PROTECT,
        related_name="voice_proposals",
    )
    transcript = models.TextField(blank=True)
    extracted_data = models.JSONField(default=dict, blank=True)
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.PROCESSING)
    clarification = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at", "-id"]

    def clean(self):
        super().clean()
        if self.status == self.Status.DRAFT_READY and self.simple_entry_id is None:
            raise ValidationError({"simple_entry": "A draft-ready proposal must link its draft."})

    def __str__(self):
        return f"Voice proposal #{self.pk or 'new'} ({self.status})"

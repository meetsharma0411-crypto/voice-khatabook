"""Customer records; ledger balances are derived from khata entries."""
from django.db import models
from django.utils import timezone


class CustomerQuerySet(models.QuerySet):
    def delete(self):
        count = self.count()
        self.update(is_active=False, updated_at=timezone.now())
        return count, {self.model._meta.label: count}


class Customer(models.Model):
    name = models.CharField(max_length=160)
    mobile_number = models.CharField(max_length=20, db_index=True)
    address = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = CustomerQuerySet.as_manager()

    class Meta:
        ordering = ["name", "id"]

    def __str__(self):
        return f"{self.name} ({self.mobile_number})"

    def delete(self, *args, **kwargs):
        self.is_active = False
        self.save(update_fields=("is_active", "updated_at"))
        return 1, {self._meta.label: 1}

from django.contrib import admin

from .models import KhataTransaction, KhataTransactionItem, LedgerEntry, SimpleKhataEntry


class KhataTransactionItemInline(admin.TabularInline):
    model = KhataTransactionItem
    extra = 0
    can_delete = False
    readonly_fields = (
        "product",
        "product_name",
        "quantity",
        "unit",
        "unit_price",
        "line_total",
    )


@admin.register(KhataTransaction)
class KhataTransactionAdmin(admin.ModelAdmin):
    list_display = ("id", "customer", "status", "transaction_date", "total_amount", "source")
    list_filter = ("status", "source", "transaction_date")
    search_fields = ("customer__name", "customer__mobile_number")
    readonly_fields = (
        "customer",
        "status",
        "source",
        "transaction_date",
        "total_amount",
        "notes",
        "ledger_entry",
        "created_by",
        "created_at",
        "updated_at",
    )
    inlines = (KhataTransactionItemInline,)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(LedgerEntry)
class LedgerEntryAdmin(admin.ModelAdmin):
    list_display = (
        "customer",
        "entry_type",
        "status",
        "transaction_date",
        "debit_amount",
        "credit_amount",
    )
    list_filter = ("entry_type", "status", "transaction_date")
    search_fields = ("customer__name", "customer__mobile_number", "notes")
    readonly_fields = ("created_at", "reversal_of")

    def has_delete_permission(self, request, obj=None):
        if obj is not None and obj.status == LedgerEntry.Status.POSTED:
            return False
        return super().has_delete_permission(request, obj)


@admin.register(SimpleKhataEntry)
class SimpleKhataEntryAdmin(admin.ModelAdmin):
    list_display = (
        "id", "customer", "transaction_type", "amount", "status", "transaction_date", "source"
    )
    list_filter = ("transaction_type", "status", "source", "transaction_date")
    search_fields = ("customer__name", "customer__mobile_number", "description", "idempotency_key")
    readonly_fields = tuple(field.name for field in SimpleKhataEntry._meta.fields)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

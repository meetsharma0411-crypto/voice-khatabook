from django.contrib import admin

from .models import Customer


@admin.register(Customer)
class CustomerAdmin(admin.ModelAdmin):
    list_display = ("name", "mobile_number", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("name", "mobile_number")
    list_editable = ("is_active",)

    def has_delete_permission(self, request, obj=None):
        return False

from django.contrib import admin

from .models import Product, ProductPrice


class ProductPriceInline(admin.TabularInline):
    model = ProductPrice
    extra = 1


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ("name", "default_unit", "current_price", "is_active")
    list_filter = ("is_active",)
    search_fields = ("name",)
    inlines = (ProductPriceInline,)


@admin.register(ProductPrice)
class ProductPriceAdmin(admin.ModelAdmin):
    list_display = ("product", "price", "effective_from")
    list_filter = ("effective_from",)
    search_fields = ("product__name",)

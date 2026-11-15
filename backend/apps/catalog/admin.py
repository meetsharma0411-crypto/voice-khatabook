from django.contrib import admin

from .models import Product, ProductAlias, ProductPrice


class ProductAliasInline(admin.TabularInline):
    model = ProductAlias
    extra = 1


class ProductPriceInline(admin.TabularInline):
    model = ProductPrice
    extra = 1


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ("name", "default_unit", "current_price", "is_active")
    list_filter = ("is_active",)
    search_fields = ("name", "aliases__alias")
    inlines = (ProductPriceInline, ProductAliasInline)


@admin.register(ProductPrice)
class ProductPriceAdmin(admin.ModelAdmin):
    list_display = ("product", "price", "effective_from")
    list_filter = ("effective_from",)
    search_fields = ("product__name",)


@admin.register(ProductAlias)
class ProductAliasAdmin(admin.ModelAdmin):
    list_display = ("alias", "product", "language")
    list_filter = ("language",)
    search_fields = ("alias", "product__name")

from django.db.models import Prefetch
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Product, ProductPrice
from .serializers import ProductPriceCreateSerializer, ProductSerializer


class ProductViewSet(viewsets.ModelViewSet):
    serializer_class = ProductSerializer
    queryset = Product.objects.prefetch_related(
        Prefetch("prices", queryset=ProductPrice.objects.order_by("-effective_from", "-id"))
    )
    search_fields = ("name",)
    ordering_fields = ("name", "created_at")

    def destroy(self, request, *args, **kwargs):
        product = self.get_object()
        product.is_active = False
        product.save(update_fields=("is_active", "updated_at"))
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="prices")
    def add_price(self, request, pk=None):
        product = get_object_or_404(Product, pk=pk)
        serializer = ProductPriceCreateSerializer(data=request.data, context={"product": product})
        serializer.is_valid(raise_exception=True)
        price = serializer.save()
        return Response(
            {"id": price.id, "price": str(price.price), "effective_from": price.effective_from},
            status=status.HTTP_201_CREATED,
        )

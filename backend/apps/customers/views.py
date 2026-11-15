from decimal import Decimal

from django.db.models import DecimalField, ExpressionWrapper, F, OuterRef, Q, Subquery, Sum, Value
from django.db.models.functions import Coalesce
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Customer
from .serializers import CustomerSerializer
from apps.khata.models import LedgerEntry


class CustomerViewSet(viewsets.ModelViewSet):
    """Customer CRUD endpoint; financial history belongs to the khata API."""

    serializer_class = CustomerSerializer
    search_fields = ("name", "mobile_number")
    ordering_fields = ("name", "created_at")

    def get_queryset(self):
        balance_field = DecimalField(max_digits=14, decimal_places=2)
        posted_balances = (
            LedgerEntry.objects.filter(
                customer_id=OuterRef("pk"),
                status=LedgerEntry.Status.POSTED,
            )
            .order_by()
            .values("customer_id")
            .annotate(
                amount=Sum(
                    ExpressionWrapper(
                        F("debit_amount") - F("credit_amount"),
                        output_field=balance_field,
                    )
                )
            )
            .values("amount")
        )
        return Customer.objects.annotate(
            current_balance=Coalesce(
                Subquery(posted_balances, output_field=balance_field),
                Value(Decimal("0.00"), output_field=balance_field),
                output_field=balance_field,
            )
        )

    @action(detail=False, methods=["get"])
    def search(self, request):
        query = request.query_params.get("search", "").strip()
        if not query:
            return Response({"detail": "Provide a search query."}, status=status.HTTP_400_BAD_REQUEST)
        customers = self.get_queryset().filter(
            Q(name__icontains=query) | Q(mobile_number__icontains=query)
        )
        return Response(self.get_serializer(customers, many=True).data)

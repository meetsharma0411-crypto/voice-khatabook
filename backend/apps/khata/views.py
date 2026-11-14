from decimal import Decimal

from django.shortcuts import get_object_or_404
from rest_framework.generics import ListAPIView
from rest_framework.response import Response

from apps.customers.models import Customer

from .models import LedgerEntry
from .serializers import LedgerEntrySerializer


class CustomerLedgerView(ListAPIView):
    """Read-only, customer-specific running ledger."""

    serializer_class = LedgerEntrySerializer

    def get_queryset(self):
        self.customer = get_object_or_404(Customer, pk=self.kwargs["customer_id"])
        return LedgerEntry.objects.filter(
            customer=self.customer,
            status=LedgerEntry.Status.POSTED,
        ).select_related("customer")

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        balance = Decimal("0.00")
        results = []
        for entry in queryset:
            balance += entry.debit_amount - entry.credit_amount
            data = self.get_serializer(entry).data
            data["running_balance"] = f"{balance:.2f}"
            results.append(data)
        return Response(results)

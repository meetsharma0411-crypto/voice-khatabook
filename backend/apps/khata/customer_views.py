"""Read-only customer transaction history and balance APIs."""
from decimal import Decimal

from django.shortcuts import get_object_or_404
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.customers.models import Customer

from .entry_serializers import LedgerHistorySerializer
from .models import LedgerEntry
from .services import get_customer_balance


class CustomerTransactionsView(ListAPIView):
    serializer_class = LedgerHistorySerializer

    def get_queryset(self):
        self.customer = get_object_or_404(Customer, pk=self.kwargs["customer_id"])
        return LedgerEntry.objects.filter(
            customer=self.customer, status=LedgerEntry.Status.POSTED
        ).select_related("customer", "reversal_of", "created_by")

    def list(self, request, *args, **kwargs):
        entries = self.filter_queryset(self.get_queryset())
        running_balance = Decimal("0.00")
        results = []
        for entry in entries:
            running_balance += entry.debit_amount - entry.credit_amount
            row = self.get_serializer(entry).data
            row["running_balance"] = f"{running_balance:.2f}"
            results.append(row)
        return Response(results)


class CustomerBalanceView(APIView):
    def get(self, request, customer_id):
        customer = get_object_or_404(Customer, pk=customer_id)
        return Response(
            {
                "customer": customer.pk,
                "customer_name": customer.name,
                "balance": str(get_customer_balance(customer.pk)),
                "meaning": "positive means customer owes the business; negative means business owes the customer",
            }
        )

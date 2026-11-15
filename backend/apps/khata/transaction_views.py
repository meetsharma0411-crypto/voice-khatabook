from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from .models import KhataTransaction, LedgerEntry
from .transaction_serializers import KhataTransactionSerializer


class KhataTransactionViewSet(viewsets.ModelViewSet):
    serializer_class = KhataTransactionSerializer
    queryset = KhataTransaction.objects.select_related(
        "customer", "ledger_entry", "ledger_entry__reversal_entry"
    ).prefetch_related("items")
    http_method_names = ["get", "post", "head", "options"]

    @action(detail=True, methods=["post"])
    def confirm(self, request, pk=None):
        with transaction.atomic():
            sale = get_object_or_404(
                KhataTransaction.objects.select_for_update(),
                pk=pk,
            )
            if sale.status != KhataTransaction.Status.DRAFT:
                raise ValidationError("Only a draft transaction can be confirmed.")
            if not sale.items.exists() or sale.total_amount <= 0:
                raise ValidationError("A transaction needs at least one priced item before confirmation.")

            ledger_entry = LedgerEntry.objects.create(
                customer=sale.customer,
                entry_type=LedgerEntry.EntryType.SALE,
                status=LedgerEntry.Status.POSTED,
                transaction_date=sale.transaction_date,
                debit_amount=sale.total_amount,
                notes=f"Sale transaction #{sale.pk}",
                created_by=request.user if request.user.is_authenticated else None,
            )
            sale.status = KhataTransaction.Status.POSTED
            sale.ledger_entry = ledger_entry
            sale.save(update_fields=("status", "ledger_entry", "updated_at"))

        return Response(self.get_serializer(sale).data)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        sale = get_object_or_404(KhataTransaction, pk=pk)
        if sale.status != KhataTransaction.Status.DRAFT:
            raise ValidationError("Only a draft transaction can be cancelled.")
        sale.status = KhataTransaction.Status.CANCELLED
        sale.save(update_fields=("status", "updated_at"))
        return Response(self.get_serializer(sale).data, status=status.HTTP_200_OK)

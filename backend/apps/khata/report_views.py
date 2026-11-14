"""Business dashboard and financial summary APIs."""
from decimal import Decimal

from django.db.models import Q, Sum
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.customers.models import Customer

from .models import LedgerEntry


def _summary_data():
    posted = LedgerEntry.objects.filter(status=LedgerEntry.Status.POSTED)
    totals = posted.aggregate(
        debits=Sum("debit_amount"),
        credits=Sum("credit_amount"),
        udhaar=Sum(
            "debit_amount",
            filter=Q(entry_type__in=(LedgerEntry.EntryType.UDHAAR, LedgerEntry.EntryType.SALE)),
        ),
        udhaar_reversed=Sum(
            "credit_amount",
            filter=Q(
                entry_type=LedgerEntry.EntryType.REVERSAL,
                reversal_of__entry_type__in=(LedgerEntry.EntryType.UDHAAR, LedgerEntry.EntryType.SALE),
            ),
        ),
        jama=Sum(
            "credit_amount",
            filter=Q(entry_type__in=(LedgerEntry.EntryType.JAMA, LedgerEntry.EntryType.PAYMENT)),
        ),
        jama_reversed=Sum(
            "debit_amount",
            filter=Q(
                entry_type=LedgerEntry.EntryType.REVERSAL,
                reversal_of__entry_type__in=(LedgerEntry.EntryType.JAMA, LedgerEntry.EntryType.PAYMENT),
            ),
        ),
    )
    zero = Decimal("0.00")
    debit_total = totals["debits"] or zero
    credit_total = totals["credits"] or zero
    return {
        "total_customers": Customer.objects.filter(is_active=True).count(),
        "total_udhaar": str((totals["udhaar"] or zero) - (totals["udhaar_reversed"] or zero)),
        "total_jama": str((totals["jama"] or zero) - (totals["jama_reversed"] or zero)),
        "total_outstanding_balance": str(debit_total - credit_total),
    }


class DashboardView(APIView):
    def get(self, request):
        return Response(_summary_data())


class SummaryReportView(APIView):
    def get(self, request):
        return Response(_summary_data())

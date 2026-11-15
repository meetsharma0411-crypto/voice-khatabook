from django.urls import path

from rest_framework.routers import DefaultRouter

from .entry_views import LedgerEntryReversalView
from .transaction_views import KhataTransactionViewSet
from .views import CustomerLedgerView


router = DefaultRouter()
router.register("transactions", KhataTransactionViewSet, basename="khata-transaction")


urlpatterns = [
    path("customers/<int:customer_id>/ledger/", CustomerLedgerView.as_view(), name="customer-ledger"),
    path("ledger/<int:ledger_entry_id>/reverse/", LedgerEntryReversalView.as_view({"post": "create"}), name="ledger-entry-reversal"),
] + router.urls

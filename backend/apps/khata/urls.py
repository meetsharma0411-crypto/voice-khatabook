from django.urls import path

from rest_framework.routers import DefaultRouter

from .transaction_views import KhataTransactionViewSet
from .views import CustomerLedgerView


router = DefaultRouter()
router.register("transactions", KhataTransactionViewSet, basename="khata-transaction")


urlpatterns = [
    path("customers/<int:customer_id>/ledger/", CustomerLedgerView.as_view(), name="customer-ledger"),
] + router.urls

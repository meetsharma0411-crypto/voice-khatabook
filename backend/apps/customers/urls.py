from rest_framework.routers import DefaultRouter

from apps.khata.customer_views import CustomerBalanceView, CustomerTransactionsView

from .views import CustomerViewSet
from django.urls import path


router = DefaultRouter()
router.register("", CustomerViewSet, basename="customer")
urlpatterns = [
    path("<int:customer_id>/transactions/", CustomerTransactionsView.as_view(), name="customer-transactions"),
    path("<int:customer_id>/balance/", CustomerBalanceView.as_view(), name="customer-balance"),
] + router.urls

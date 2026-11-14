"""Root URL configuration."""
from django.contrib import admin
from django.urls import include, path


urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/customers/", include("apps.customers.urls")),
    path("api/", include("apps.catalog.urls")),
    path("api/khata/", include("apps.khata.urls")),
    path("api/transactions/", include("apps.khata.entry_urls")),
    path("api/", include("apps.khata.report_urls")),
]

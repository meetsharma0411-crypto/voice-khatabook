"""Root URL configuration."""
from django.contrib import admin
from django.urls import include, path
from apps.common.auth_views import KhataLoginView, KhataLogoutView
from rest_framework_simplejwt.views import TokenRefreshView


urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/auth/token/", KhataLoginView.as_view(), name="auth-token-obtain"),
    path("api/auth/token/refresh/", TokenRefreshView.as_view(), name="auth-token-refresh"),
    path("api/auth/logout/", KhataLogoutView.as_view(), name="auth-logout"),
    path("api/customers/", include("apps.customers.urls")),
    path("api/voice/", include("apps.voice.urls")),
    path("api/", include("apps.catalog.urls")),
    path("api/khata/", include("apps.khata.urls")),
    path("api/transactions/", include("apps.khata.entry_urls")),
    path("api/", include("apps.khata.report_urls")),
]

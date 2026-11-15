from rest_framework.permissions import AllowAny
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.views import TokenBlacklistView, TokenObtainPairView


class KhataLoginView(TokenObtainPairView):
    """Issue access and refresh tokens with a scoped per-IP login limit."""

    permission_classes = (AllowAny,)
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = "auth_login"


class KhataLogoutView(TokenBlacklistView):
    """Revoke the submitted refresh token; possession of it authorizes logout."""

    permission_classes = (AllowAny,)

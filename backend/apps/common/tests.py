from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken


class JwtAuthenticationApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.username = "mobile-operator"
        self.password = "A-strong-test-password-318!"
        get_user_model().objects.create_user(
            username=self.username,
            password=self.password,
        )
        self.client = APIClient()

    def test_login_returns_access_and_refresh_tokens(self):
        response = self.client.post(
            "/api/auth/token/",
            {"username": self.username, "password": self.password},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["access"])
        self.assertTrue(response.data["refresh"])

    def test_invalid_login_is_rejected(self):
        response = self.client.post(
            "/api/auth/token/",
            {"username": self.username, "password": "wrong-password"},
            format="json",
        )
        self.assertEqual(response.status_code, 401)

    def test_login_is_rate_limited(self):
        for _ in range(5):
            self.client.post(
                "/api/auth/token/",
                {"username": self.username, "password": "wrong-password"},
                format="json",
            )

        response = self.client.post(
            "/api/auth/token/",
            {"username": self.username, "password": "wrong-password"},
            format="json",
        )

        self.assertEqual(response.status_code, 429)

    def test_access_token_authenticates_customer_api(self):
        tokens = self._login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

        response = self.client.get("/api/customers/")

        self.assertEqual(response.status_code, 200)

    def test_refresh_rotates_token_and_blacklists_previous_refresh(self):
        tokens = self._login()

        response = self.client.post(
            "/api/auth/token/refresh/",
            {"refresh": tokens["refresh"]},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["access"])
        self.assertNotEqual(response.data["refresh"], tokens["refresh"])
        replay = self.client.post(
            "/api/auth/token/refresh/",
            {"refresh": tokens["refresh"]},
            format="json",
        )
        self.assertEqual(replay.status_code, 401)

    def test_logout_blacklists_refresh_token(self):
        tokens = self._login()

        response = self.client.post(
            "/api/auth/logout/",
            {"refresh": tokens["refresh"]},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(BlacklistedToken.objects.count(), 1)
        refresh = self.client.post(
            "/api/auth/token/refresh/",
            {"refresh": tokens["refresh"]},
            format="json",
        )
        self.assertEqual(refresh.status_code, 401)

    def _login(self):
        response = self.client.post(
            "/api/auth/token/",
            {"username": self.username, "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        return response.data

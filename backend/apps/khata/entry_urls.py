from rest_framework.routers import DefaultRouter

from .entry_views import SimpleKhataEntryViewSet


router = DefaultRouter()
router.register("", SimpleKhataEntryViewSet, basename="simple-khata-entry")
urlpatterns = router.urls

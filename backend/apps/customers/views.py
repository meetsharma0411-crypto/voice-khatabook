from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Customer
from .serializers import CustomerSerializer


class CustomerViewSet(viewsets.ModelViewSet):
    """Customer CRUD endpoint; financial history belongs to the khata API."""

    queryset = Customer.objects.all()
    serializer_class = CustomerSerializer
    search_fields = ("name", "mobile_number")
    ordering_fields = ("name", "created_at")

    @action(detail=False, methods=["get"])
    def search(self, request):
        query = request.query_params.get("search", "").strip()
        if not query:
            return Response({"detail": "Provide a search query."}, status=status.HTTP_400_BAD_REQUEST)
        customers = self.get_queryset().filter(
            Q(name__icontains=query) | Q(mobile_number__icontains=query)
        )
        return Response(self.get_serializer(customers, many=True).data)

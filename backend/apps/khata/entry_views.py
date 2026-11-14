"""Authenticated APIs for simple Udhaar/Jama drafts and posting."""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response

from .entry_serializers import ReversalSerializer, SimpleKhataEntryCreateSerializer, SimpleKhataEntrySerializer
from .models import LedgerEntry, SimpleKhataEntry
from .services import IdempotencyConflict, confirm_simple_entry, create_simple_entry, reverse_ledger_entry


def _as_api_validation_error(error):
    detail = error.message_dict if hasattr(error, "message_dict") else error.messages
    raise ValidationError(detail)


class SimpleKhataEntryViewSet(viewsets.ModelViewSet):
    """Create drafts; posting and corrections have explicit actions."""

    serializer_class = SimpleKhataEntrySerializer
    queryset = SimpleKhataEntry.objects.select_related("customer", "ledger_entry", "created_by")
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        queryset = super().get_queryset()
        customer_id = self.request.query_params.get("customer")
        transaction_type = self.request.query_params.get("transaction_type")
        if customer_id:
            queryset = queryset.filter(customer_id=customer_id)
        if transaction_type:
            queryset = queryset.filter(transaction_type=transaction_type)
        return queryset

    def create(self, request, *args, **kwargs):
        key = request.headers.get("Idempotency-Key", "").strip()
        if not key:
            raise ValidationError({"Idempotency-Key": "This header is required."})
        if len(key) > 128:
            raise ValidationError({"Idempotency-Key": "Maximum length is 128 characters."})

        input_serializer = SimpleKhataEntryCreateSerializer(data=request.data)
        input_serializer.is_valid(raise_exception=True)
        try:
            entry, created = create_simple_entry(
                **input_serializer.validated_data,
                idempotency_key=key,
                created_by=request.user,
            )
        except IdempotencyConflict:
            return Response(
                {"detail": "This idempotency key was already used with a different payload."},
                status=status.HTTP_409_CONFLICT,
            )
        except DjangoValidationError as error:
            _as_api_validation_error(error)

        output = self.get_serializer(entry).data
        return Response(output, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    @action(detail=True, methods=["post"])
    def confirm(self, request, pk=None):
        try:
            entry, balance, _created = confirm_simple_entry(entry_id=pk, actor=request.user)
        except SimpleKhataEntry.DoesNotExist:
            raise NotFound("Transaction not found.")
        except DjangoValidationError as error:
            _as_api_validation_error(error)
        return Response({**self.get_serializer(entry).data, "balance_after": str(balance)})

    @action(detail=True, methods=["post"])
    def reverse(self, request, pk=None):
        entry = get_object_or_404(self.get_queryset(), pk=pk)
        if entry.status != SimpleKhataEntry.Status.POSTED or not entry.ledger_entry_id:
            raise ValidationError("Only a posted transaction can be reversed.")
        reason_serializer = ReversalSerializer(data=request.data)
        reason_serializer.is_valid(raise_exception=True)
        try:
            reversal, balance = reverse_ledger_entry(
                ledger_entry_id=entry.ledger_entry_id,
                reason=reason_serializer.validated_data["reason"],
                actor=request.user,
            )
        except LedgerEntry.DoesNotExist:
            raise NotFound("Ledger transaction not found.")
        except DjangoValidationError as error:
            _as_api_validation_error(error)
        return Response(
            {
                "original_ledger_entry": entry.ledger_entry_id,
                "reversal_ledger_entry": reversal.pk,
                "reason": reversal.notes,
                "balance_after": str(balance),
            },
            status=status.HTTP_201_CREATED,
        )

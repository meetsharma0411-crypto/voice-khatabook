import hashlib
import mimetypes
import tempfile

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.customers.models import Customer
from apps.khata.entry_serializers import SimpleKhataEntrySerializer
from apps.khata.services import preview_simple_entry

from .models import BusinessKnowledge, VoiceProposal
from .serializers import (
    BusinessKnowledgeSerializer,
    VoiceAudioUploadSerializer,
    VoiceCustomerResolveSerializer,
    VoiceProposalSerializer,
)
from .services import (
    GeminiVoiceProvider,
    VoiceProviderError,
    create_voice_draft,
    evaluate_extraction,
    normalize_name,
    safe_extraction_json,
    transcribe_and_extract,
)


def _proposal_response(proposal, *, candidates=None):
    body = VoiceProposalSerializer(proposal).data
    body["customer_candidates"] = [
        {"id": customer.pk, "name": customer.name, "mobile_number": customer.mobile_number}
        for customer in (candidates or [])
    ]
    if proposal.simple_entry_id:
        entry = proposal.simple_entry
        body["draft"] = SimpleKhataEntrySerializer(entry).data
        if entry.status == "draft":
            _entry, previous, projected = preview_simple_entry(entry_id=entry.pk)
            body["preview"] = {
                "previous_balance": f"{previous:.2f}",
                "projected_balance": f"{projected:.2f}",
            }
        else:
            body["status"] = entry.status
            if entry.status == "posted":
                body["clarification"] = "This voice entry was already confirmed and posted."
            elif entry.status == "cancelled":
                body["clarification"] = "This voice draft was cancelled and was not posted."
            body["preview"] = None
    else:
        body["draft"] = None
        body["preview"] = None
    return body


def _request_hash(upload):
    digest = hashlib.sha256()
    upload.seek(0)
    for chunk in upload.chunks():
        digest.update(chunk)
    upload.seek(0)
    return digest.hexdigest()


def _candidate_customers(name):
    normalized = normalize_name(name)
    if not normalized:
        return []
    return list(
        Customer.objects.filter(is_active=True)
        .filter(Q(name__icontains=name.strip()))
        .only("id", "name", "mobile_number")[:10]
    )


class VoiceProposalCreateView(APIView):
    parser_classes = (MultiPartParser, FormParser)
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = "voice_ai"

    def post(self, request):
        key = request.headers.get("Idempotency-Key", "").strip()
        if not key or len(key) > 120:
            return Response(
                {"detail": "A unique Idempotency-Key of 1 to 120 characters is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = VoiceAudioUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        audio = serializer.validated_data["audio"]
        requested_customer = serializer.validated_data.get("customer")
        audio_hash = _request_hash(audio)

        existing = VoiceProposal.objects.filter(idempotency_key=key).first()
        if existing:
            if (existing.user_id != request.user.pk or existing.audio_sha256 != audio_hash
                    or existing.requested_customer_id != getattr(requested_customer, "pk", None)):
                return Response({"detail": "This idempotency key was already used with different request data."}, status=409)
            if existing.status == VoiceProposal.Status.FAILED:
                with transaction.atomic():
                    proposal = VoiceProposal.objects.select_for_update().get(pk=existing.pk)
                    if proposal.status == VoiceProposal.Status.FAILED:
                        proposal.status = VoiceProposal.Status.PROCESSING
                        proposal.clarification = ""
                        proposal.save(update_fields=("status", "clarification", "updated_at"))
                    else:
                        return Response(_proposal_response(proposal), status=status.HTTP_202_ACCEPTED)
            else:
                return Response(
                    _proposal_response(existing, candidates=_candidate_customers(
                        (existing.extracted_data or {}).get("customer_name")
                    )),
                    status=status.HTTP_202_ACCEPTED if existing.status == VoiceProposal.Status.PROCESSING else status.HTTP_200_OK,
                )
        else:
            try:
                with transaction.atomic():
                    proposal = VoiceProposal.objects.create(
                        user=request.user,
                        idempotency_key=key,
                        audio_sha256=audio_hash,
                        requested_customer=requested_customer,
                    )
            except IntegrityError:
                existing = VoiceProposal.objects.get(idempotency_key=key)
                if (existing.user_id != request.user.pk or existing.audio_sha256 != audio_hash
                        or existing.requested_customer_id != getattr(requested_customer, "pk", None)):
                    return Response({"detail": "This idempotency key was already used with different request data."}, status=409)
                return Response(_proposal_response(existing), status=202)

        extension = mimetypes.guess_extension(audio.content_type or "") or ".m4a"
        if extension == ".mp4":
            extension = ".m4a"
        try:
            with tempfile.TemporaryDirectory(prefix="keshav_voice_") as temporary_directory:
                audio_path = f"{temporary_directory}/recording{extension}"
                with open(audio_path, "wb") as temporary:
                    for chunk in audio.chunks():
                        temporary.write(chunk)
                transcript, extraction = transcribe_and_extract(audio_path)
            proposal.transcript = transcript
            proposal.extracted_data = safe_extraction_json(extraction)
            evaluation = evaluate_extraction(
                extraction,
                requested_customer=requested_customer,
            )
            proposal.status = evaluation["status"]
            proposal.clarification = evaluation["clarification"]
            proposal.save(update_fields=("transcript", "extracted_data", "status", "clarification", "updated_at"))
            candidates = evaluation["candidates"]
            if evaluation["status"] == VoiceProposal.Status.DRAFT_READY:
                proposal, _evaluation, _preview = create_voice_draft(
                    proposal=proposal,
                    customer=evaluation["customer"],
                    actor=request.user,
                    idempotency_key=key,
                )
            response_status = status.HTTP_201_CREATED
            return Response(_proposal_response(proposal, candidates=candidates), status=response_status)
        except VoiceProviderError as error:
            proposal.status = VoiceProposal.Status.FAILED
            proposal.clarification = str(error)
            proposal.save(update_fields=("status", "clarification", "updated_at"))
            code = status.HTTP_503_SERVICE_UNAVAILABLE if "not configured" in str(error) else status.HTTP_502_BAD_GATEWAY
            return Response(_proposal_response(proposal), status=code)
        except DjangoValidationError as error:
            detail = error.message_dict if hasattr(error, "message_dict") else error.messages
            proposal.status = VoiceProposal.Status.NEEDS_CLARIFICATION
            proposal.clarification = str(detail)
            proposal.save(update_fields=("status", "clarification", "updated_at"))
            return Response(_proposal_response(proposal), status=status.HTTP_200_OK)


class VoiceProposalResolveCustomerView(APIView):
    def post(self, request, proposal_id):
        proposal = get_object_or_404(
            VoiceProposal.objects.select_related("requested_customer", "customer", "simple_entry"),
            pk=proposal_id,
            user=request.user,
        )
        serializer = VoiceCustomerResolveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        customer = serializer.validated_data["customer"]
        if proposal.status == VoiceProposal.Status.DRAFT_READY:
            return Response(_proposal_response(proposal), status=status.HTTP_200_OK)
        if proposal.status != VoiceProposal.Status.NEEDS_CUSTOMER:
            return Response({"detail": "This proposal is not waiting for a customer choice."}, status=409)
        try:
            proposal, _evaluation, _preview = create_voice_draft(
                proposal=proposal,
                customer=customer,
                actor=request.user,
                idempotency_key=proposal.idempotency_key,
            )
        except DjangoValidationError as error:
            detail = error.message_dict if hasattr(error, "message_dict") else error.messages
            return Response({"detail": detail}, status=400)
        candidates = _candidate_customers((proposal.extracted_data or {}).get("customer_name"))
        return Response(_proposal_response(proposal, candidates=candidates), status=200)


class BusinessKnowledgeSearchView(APIView):
    def get(self, request):
        queryset = BusinessKnowledge.objects.filter(is_active=True)
        term = request.query_params.get("search", "").strip()
        if term:
            queryset = queryset.filter(Q(title__icontains=term) | Q(content__icontains=term))
        rows = queryset[:50]
        return Response(BusinessKnowledgeSerializer(rows, many=True).data)

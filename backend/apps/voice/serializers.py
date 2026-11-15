from rest_framework import serializers

from apps.customers.models import Customer

from .models import BusinessKnowledge, VoiceProposal


class VoiceAudioUploadSerializer(serializers.Serializer):
    audio = serializers.FileField()
    customer_id = serializers.PrimaryKeyRelatedField(
        source="customer", queryset=Customer.objects.filter(is_active=True),
        required=False, allow_null=True,
    )

    def validate_audio(self, audio):
        if audio.size <= 0:
            raise serializers.ValidationError("The recording is empty.")
        if audio.size > 10 * 1024 * 1024:
            raise serializers.ValidationError("Recording must be 10 MB or smaller.")
        allowed = {
            "audio/m4a", "audio/mp4", "audio/aac", "audio/ogg", "audio/webm",
            "audio/wav", "audio/x-wav", "audio/mpeg", "audio/3gpp", "audio/opus",
        }
        if (audio.content_type or "").lower() not in allowed:
            raise serializers.ValidationError("Use an M4A, AAC, OGG, WebM, WAV, MP3, or Opus recording.")
        return audio


class VoiceCustomerResolveSerializer(serializers.Serializer):
    customer_id = serializers.PrimaryKeyRelatedField(
        source="customer", queryset=Customer.objects.filter(is_active=True),
    )


class VoiceProposalSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source="customer.name", read_only=True, allow_null=True)
    transaction_id = serializers.IntegerField(source="simple_entry_id", read_only=True, allow_null=True)

    class Meta:
        model = VoiceProposal
        fields = (
            "id", "status", "transcript", "extracted_data", "customer",
            "customer_name", "transaction_id", "clarification", "created_at",
        )
        read_only_fields = fields


class BusinessKnowledgeSerializer(serializers.ModelSerializer):
    class Meta:
        model = BusinessKnowledge
        fields = ("id", "category", "title", "content", "keywords", "updated_at")
        read_only_fields = fields

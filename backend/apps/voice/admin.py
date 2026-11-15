from django.contrib import admin

from .models import BusinessKnowledge, VoiceProposal


@admin.register(BusinessKnowledge)
class BusinessKnowledgeAdmin(admin.ModelAdmin):
    list_display = ("title", "category", "is_active", "updated_at")
    list_filter = ("category", "is_active")
    search_fields = ("title", "content")


@admin.register(VoiceProposal)
class VoiceProposalAdmin(admin.ModelAdmin):
    list_display = ("id", "status", "user", "customer", "created_at")
    list_filter = ("status", "created_at")
    search_fields = ("transcript", "customer__name")
    readonly_fields = tuple(field.name for field in VoiceProposal._meta.fields)

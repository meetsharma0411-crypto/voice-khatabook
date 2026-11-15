from django.urls import path

from .views import (
    BusinessKnowledgeSearchView,
    VoiceProposalCreateView,
    VoiceProposalResolveCustomerView,
)


urlpatterns = [
    path("proposals/", VoiceProposalCreateView.as_view(), name="voice-proposals"),
    path(
        "proposals/<int:proposal_id>/customer/",
        VoiceProposalResolveCustomerView.as_view(),
        name="voice-proposal-customer",
    ),
    path("knowledge/", BusinessKnowledgeSearchView.as_view(), name="voice-knowledge-search"),
]

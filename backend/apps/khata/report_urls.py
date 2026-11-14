from django.urls import path

from .report_views import DashboardView, SummaryReportView


urlpatterns = [
    path("dashboard/", DashboardView.as_view(), name="dashboard"),
    path("reports/summary/", SummaryReportView.as_view(), name="summary-report"),
]

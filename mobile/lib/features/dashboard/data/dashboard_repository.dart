import '../../../core/network/api_client.dart';
import '../domain/dashboard_summary.dart';

class DashboardRepository {
  DashboardRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardSummary> load() async => DashboardSummary.fromJson(
    Map<String, dynamic>.from(await _apiClient.get('dashboard/') as Map),
  );
}

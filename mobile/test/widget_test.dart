import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/app.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/dashboard/data/dashboard_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/dashboard/domain/dashboard_summary.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/data/khata_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/domain/khata_transaction.dart';

void main() {
  testWidgets('dashboard and navigation render', (tester) async {
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(
      const AuthTokens(access: 'access-test', refresh: 'refresh-test'),
    );
    await tester.pumpWidget(
      KeshavKhataApp(
        authTokenStore: tokenStore,
        dashboardRepository: _FakeDashboardRepository(),
        khataRepository: _FakeKhataRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Business overview'), findsOneWidget);
    expect(find.text('Customers'), findsNWidgets(2));
    expect(find.text('Khata'), findsOneWidget);
    await tester.tap(find.text('Khata'));
    await tester.pumpAndSettle();
    expect(find.text('No posted Khata entries yet.'), findsOneWidget);
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('Voice Khata'), findsOneWidget);
    expect(find.text('Start recording'), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Keshav Dairy & Beverages'), findsOneWidget);
  });

  testWidgets('app opens at sign in when no token pair is stored', (
    tester,
  ) async {
    await tester.pumpWidget(
      KeshavKhataApp(authTokenStore: MemoryAuthTokenStore()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to KhataBook'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });
}

class _FakeKhataRepository extends KhataRepository {
  _FakeKhataRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );

  @override
  Future<List<PostedKhataTransaction>> listPosted({int? customerId}) async =>
      const [];
}

class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );

  @override
  Future<DashboardSummary> load() async => const DashboardSummary(
    totalCustomers: 2,
    totalUdhaar: '200.00',
    totalJama: '50.00',
    totalOutstandingBalance: '150.00',
    recentTransactions: [],
  );
}

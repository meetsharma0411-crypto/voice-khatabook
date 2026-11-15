import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/data/customer_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/dashboard/data/dashboard_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/dashboard/domain/dashboard_summary.dart';
import 'package:keshav_ai_voice_khatabook/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  testWidgets('dashboard shows server totals, recent row and quick actions', (
    tester,
  ) async {
    var udhaarTapped = false;
    var jamaTapped = false;
    final tokenStore = MemoryAuthTokenStore();
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1/api/',
      tokenStore: tokenStore,
    );
    final customerRepository = CustomerRepository(client);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          repository: _FakeDashboardRepository(client),
          customerRepository: customerRepository,
          onLogout: () {},
          onAddUdhaar: () async {
            udhaarTapped = true;
            return false;
          },
          onAddJama: () async {
            jamaTapped = true;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('₹ 1250.00'), findsOneWidget);
    expect(find.text('₹ 400.00'), findsOneWidget);
    expect(find.text('Mina Patel'), findsOneWidget);
    expect(find.text('Udhar · 2026-11-14'), findsOneWidget);
    await tester.tap(find.textContaining('Add Udhar'));
    await tester.tap(find.textContaining('Add Jama'));
    expect(udhaarTapped, isTrue);
    expect(jamaTapped, isTrue);
  });
}

class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository(super.client);

  @override
  Future<DashboardSummary> load() async => const DashboardSummary(
    totalCustomers: 8,
    totalUdhaar: '1250.00',
    totalJama: '400.00',
    totalOutstandingBalance: '850.00',
    recentTransactions: [
      RecentLedgerTransaction(
        id: 1,
        customerName: 'Mina Patel',
        entryType: 'udhaar',
        transactionDate: '2026-11-14',
        debitAmount: '250.00',
        creditAmount: '0.00',
        notes: '',
      ),
    ],
  );
}

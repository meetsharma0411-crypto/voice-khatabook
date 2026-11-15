import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/data/customer_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/domain/customer.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/presentation/customer_form_screen.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/presentation/customer_list_screen.dart';

void main() {
  testWidgets('customer list opens details and shows server balance', (
    tester,
  ) async {
    final repository = _FakeCustomerRepository();
    await tester.pumpWidget(
      MaterialApp(home: CustomerListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asha Patel'), findsOneWidget);
    expect(find.text('₹ 75.00'), findsOneWidget);

    await tester.tap(find.text('Asha Patel'));
    await tester.pumpAndSettle();
    expect(find.text('₹ 123.45'), findsOneWidget);
    expect(find.text('Server supplied balance meaning'), findsOneWidget);
    expect(find.text('Transaction history'), findsOneWidget);
    expect(find.text('Udhar'), findsOneWidget);
    expect(find.text('2026-11-14 · Milk bill'), findsOneWidget);
  });

  testWidgets('search sends text to repository and displays empty result', (
    tester,
  ) async {
    final repository = _FakeCustomerRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerListScreen(repository: repository, searchMode: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.queries, contains('missing'));
    expect(find.text('No customers match “missing”.'), findsOneWidget);
  });

  testWidgets('add customer form validates required fields', (tester) async {
    final repository = _FakeCustomerRepository();
    await tester.pumpWidget(
      MaterialApp(home: CustomerFormScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save customer'));
    await tester.tap(find.text('Save customer'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the customer name.'), findsOneWidget);
    expect(find.text('Enter a mobile number.'), findsOneWidget);
    expect(repository.createCalls, 0);
  });
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );

  final queries = <String>[];
  int createCalls = 0;
  final customer = const Customer(
    id: 7,
    name: 'Asha Patel',
    mobileNumber: '9876543210',
    address: 'Main Road',
    notes: '',
    isActive: true,
    currentBalance: '75.00',
  );

  @override
  Future<List<Customer>> list({String search = ''}) async {
    queries.add(search);
    return search.isEmpty ? [customer] : const [];
  }

  @override
  Future<Customer> get(int customerId) async => customer;

  @override
  Future<CustomerBalance> getBalance(int customerId) async =>
      const CustomerBalance(
        customerId: 7,
        customerName: 'Asha Patel',
        amount: '123.45',
        meaning: 'Server supplied balance meaning',
      );

  @override
  Future<List<CustomerLedgerTransaction>> getTransactions(
    int customerId,
  ) async => const [
    CustomerLedgerTransaction(
      id: 1,
      entryType: 'udhaar',
      transactionDate: '2026-11-14',
      debitAmount: '75.00',
      creditAmount: '0.00',
      notes: 'Milk bill',
      isReversed: false,
    ),
  ];

  @override
  Future<Customer> create({
    required Customer customer,
    String? openingBalanceAmount,
    String? openingBalanceSide,
  }) async {
    createCalls++;
    return this.customer;
  }
}

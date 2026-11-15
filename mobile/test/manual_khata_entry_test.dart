import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/data/customer_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/domain/customer.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/data/khata_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/domain/khata_transaction.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/presentation/manual_khata_entry_screen.dart';

void main() {
  testWidgets('manual Udhar requires explicit review and confirm', (
    tester,
  ) async {
    final khata = _FakeKhataRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualKhataEntryScreen(
          transactionType: 'udhaar',
          customerRepository: _FakeCustomerRepository(),
          khataRepository: khata,
        ),
      ),
    );

    await tester.tap(find.text('Choose customer *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Patel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '200.00');
    await tester.tap(find.text('Review before saving'));
    await tester.pumpAndSettle();
    expect(find.text('Previous balance'), findsOneWidget);
    expect(find.text('₹ 500.00'), findsOneWidget);
    expect(find.text('₹ 700.00'), findsOneWidget);
    expect(khata.confirmCalls, 0);

    await tester.tap(find.text('Confirm and save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Django will post this entry to the customer ledger.'),
      findsOneWidget,
    );
    expect(khata.confirmCalls, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm').last);
    await tester.pumpAndSettle();
    expect(khata.confirmCalls, 1);
  });

  testWidgets('invalid amount does not create a draft', (tester) async {
    final khata = _FakeKhataRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualKhataEntryScreen(
          transactionType: 'jama',
          customerRepository: _FakeCustomerRepository(),
          khataRepository: khata,
        ),
      ),
    );
    await tester.tap(find.text('Review before saving'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount.'), findsOneWidget);
    expect(khata.createCalls, 0);
  });

  testWidgets('manual Jama preview comes from the server before confirmation', (
    tester,
  ) async {
    final khata = _FakeKhataRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualKhataEntryScreen(
          transactionType: 'jama',
          customerRepository: _FakeCustomerRepository(),
          khataRepository: khata,
        ),
      ),
    );
    await tester.tap(find.text('Choose customer *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Patel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '200.00');
    await tester.tap(find.text('Review before saving'));
    await tester.pumpAndSettle();
    expect(find.text('New Jama'), findsOneWidget);
    expect(find.text('₹ 300.00'), findsOneWidget);
    expect(khata.confirmCalls, 0);
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

  static const customer = Customer(
    id: 7,
    name: 'Asha Patel',
    mobileNumber: '9876543210',
    address: '',
    notes: '',
    isActive: true,
  );

  @override
  Future<List<Customer>> list({String search = ''}) async => [customer];
}

class _FakeKhataRepository extends KhataRepository {
  _FakeKhataRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );

  int createCalls = 0;
  int confirmCalls = 0;
  String _type = 'udhaar';

  @override
  Future<KhataDraft> createDraft({
    required int customerId,
    required String type,
    required String amount,
    required String description,
    required String transactionDate,
    required String idempotencyKey,
  }) async {
    createCalls++;
    _type = type;
    return KhataDraft(
      id: 12,
      customerId: customerId,
      customerName: 'Asha Patel',
      transactionType: type,
      amount: amount,
      description: description,
      transactionDate: transactionDate,
      status: 'draft',
    );
  }

  @override
  Future<KhataPreview> preview(int draftId) async => KhataPreview(
    draft: KhataDraft(
      id: 12,
      customerId: 7,
      customerName: 'Asha Patel',
      transactionType: _type,
      amount: '200.00',
      description: '',
      transactionDate: '2026-11-15',
      status: 'draft',
    ),
    previousBalance: '500.00',
    projectedBalance: _type == 'udhaar' ? '700.00' : '300.00',
  );

  @override
  Future<String> confirm(int draftId) async {
    confirmCalls++;
    return '700.00';
  }

  @override
  Future<void> cancel(int draftId) async {}
}

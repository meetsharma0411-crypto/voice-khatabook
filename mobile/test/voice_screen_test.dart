import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/data/customer_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/customers/domain/customer.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/data/khata_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/khata/domain/khata_transaction.dart';
import 'package:keshav_ai_voice_khatabook/features/voice/data/voice_recorder.dart';
import 'package:keshav_ai_voice_khatabook/features/voice/data/voice_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/voice/domain/voice_proposal.dart';
import 'package:keshav_ai_voice_khatabook/features/voice/presentation/voice_screen.dart';

void main() {
  testWidgets(
    'voice proposal shows server preview and waits for confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = _FakeRecorder();
      final voice = _FakeVoiceRepository();
      final khata = _FakeKhataRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => VoiceScreen(
                      customerRepository: _FakeCustomerRepository(),
                      khataRepository: khata,
                      voiceRepository: voice,
                      recorder: recorder,
                    ),
                  ),
                ),
                child: const Text('Open voice'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();
      expect(find.text('Stop recording'), findsOneWidget);
      await tester.tap(find.text('Stop recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transcribe and review'));
      await tester.pumpAndSettle();

      expect(find.text('Voice transcript'), findsOneWidget);
      expect(find.text('Ramesh ne 200 rupaye udhar'), findsOneWidget);
      expect(find.text('₹ 500.00'), findsOneWidget);
      expect(find.text('₹ 700.00'), findsOneWidget);
      expect(voice.createCalls, 1);
      expect(khata.confirmCalls, 0);

      await tester.ensureVisible(find.text('Confirm and save'));
      await tester.tap(find.text('Confirm and save'));
      await tester.pumpAndSettle();
      expect(khata.confirmCalls, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm').last);
      await tester.pumpAndSettle();
      expect(khata.confirmCalls, 1);
    },
  );
}

class _FakeRecorder implements VoiceRecorder {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}fake_voice.m4a';
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String outputPath) async {}

  @override
  Future<String?> stop() async => path;
  @override
  Future<void> dispose() async {}
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );
  @override
  Future<List<Customer>> list({String search = ''}) async => const [];
}

class _FakeVoiceRepository extends VoiceRepository {
  _FakeVoiceRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );
  int createCalls = 0;
  @override
  Future<VoiceProposal> createProposal({
    required String audioPath,
    required String idempotencyKey,
    int? customerId,
  }) async {
    createCalls++;
    return const VoiceProposal(
      id: 1,
      status: 'draft_ready',
      transcript: 'Ramesh ne 200 rupaye udhar',
      interpretation: {'transaction_type': 'udhaar', 'amount': '200.00'},
      clarification: '',
      customerCandidates: [],
      draft: KhataDraft(
        id: 17,
        customerId: 4,
        customerName: 'Ramesh Patel',
        transactionType: 'udhaar',
        amount: '200.00',
        description: '',
        transactionDate: '2026-11-15',
        status: 'draft',
      ),
      preview: KhataPreview(
        draft: KhataDraft(
          id: 17,
          customerId: 4,
          customerName: 'Ramesh Patel',
          transactionType: 'udhaar',
          amount: '200.00',
          description: '',
          transactionDate: '2026-11-15',
          status: 'draft',
        ),
        previousBalance: '500.00',
        projectedBalance: '700.00',
      ),
    );
  }
}

class _FakeKhataRepository extends KhataRepository {
  _FakeKhataRepository()
    : super(
        ApiClient(
          baseUrl: 'http://127.0.0.1/api/',
          tokenStore: MemoryAuthTokenStore(),
        ),
      );
  int confirmCalls = 0;
  @override
  Future<String> confirm(int draftId) async {
    confirmCalls++;
    return '700.00';
  }

  @override
  Future<void> cancel(int draftId) async {}
}

import '../../../core/network/api_client.dart';
import '../domain/khata_transaction.dart';

class KhataRepository {
  KhataRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<KhataDraft> createDraft({
    required int customerId,
    required String type,
    required String amount,
    required String description,
    required String transactionDate,
    required String idempotencyKey,
  }) async => KhataDraft.fromJson(
    Map<String, dynamic>.from(
      await _apiClient.post(
            'transactions/',
            body: {
              'customer': customerId,
              'transaction_type': type,
              'amount': amount,
              'description': description,
              'transaction_date': transactionDate,
              'source': 'manual',
            },
            idempotencyKey: idempotencyKey,
          )
          as Map,
    ),
  );

  Future<KhataPreview> preview(int draftId) async => KhataPreview.fromJson(
    Map<String, dynamic>.from(
      await _apiClient.get('transactions/$draftId/preview/') as Map,
    ),
  );

  Future<String> confirm(int draftId) async {
    final response = Map<String, dynamic>.from(
      await _apiClient.post('transactions/$draftId/confirm/', body: const {})
          as Map,
    );
    return response['balance_after']?.toString() ?? '0.00';
  }

  Future<void> cancel(int draftId) async {
    await _apiClient.post('transactions/$draftId/cancel/', body: const {});
  }

  Future<List<PostedKhataTransaction>> listPosted({int? customerId}) async {
    final path = customerId == null
        ? 'transactions/?status=posted'
        : 'transactions/?status=posted&customer=$customerId';
    final response = await _apiClient.get(path);
    if (response is! List) {
      throw const FormatException('Unexpected khata transaction response.');
    }
    return response
        .map(
          (row) => PostedKhataTransaction.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }
}

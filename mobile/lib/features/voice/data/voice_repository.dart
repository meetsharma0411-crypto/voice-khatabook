import 'dart:io';

import '../../../core/network/api_client.dart';
import '../domain/voice_proposal.dart';

class VoiceRepository {
  VoiceRepository(this._apiClient);
  final ApiClient _apiClient;

  Future<VoiceProposal> createProposal({
    required String audioPath,
    required String idempotencyKey,
    int? customerId,
  }) async {
    final fields = <String, String>{};
    if (customerId != null) fields['customer_id'] = customerId.toString();
    final response = await _apiClient.postMultipartFile(
      path: 'voice/proposals/',
      file: File(audioPath),
      fileField: 'audio',
      fields: fields,
      idempotencyKey: idempotencyKey,
    );
    if (response is! Map) {
      throw const FormatException('Unexpected voice proposal response.');
    }
    return VoiceProposal.fromJson(Map<String, dynamic>.from(response));
  }

  Future<VoiceProposal> resolveCustomer({
    required int proposalId,
    required int customerId,
  }) async {
    final response = await _apiClient.post(
      'voice/proposals/$proposalId/customer/',
      body: {'customer_id': customerId},
    );
    if (response is! Map) {
      throw const FormatException(
        'Unexpected customer clarification response.',
      );
    }
    return VoiceProposal.fromJson(Map<String, dynamic>.from(response));
  }
}

import '../../khata/domain/khata_transaction.dart';

class VoiceProposal {
  const VoiceProposal({
    required this.id,
    required this.status,
    required this.transcript,
    required this.interpretation,
    required this.clarification,
    required this.customerCandidates,
    this.draft,
    this.preview,
  });

  final int id;
  final String status;
  final String transcript;
  final Map<String, dynamic> interpretation;
  final String clarification;
  final List<VoiceCustomerCandidate> customerCandidates;
  final KhataDraft? draft;
  final KhataPreview? preview;

  bool get needsCustomer => status == 'needs_customer';
  bool get readyForReview =>
      status == 'draft_ready' && draft != null && preview != null;

  factory VoiceProposal.fromJson(Map<String, dynamic> json) {
    final draftJson = json['draft'];
    final previewJson = json['preview'];
    final draft = draftJson is Map
        ? KhataDraft.fromJson(Map<String, dynamic>.from(draftJson))
        : null;
    KhataPreview? preview;
    if (draft != null && previewJson is Map) {
      final balances = Map<String, dynamic>.from(previewJson);
      preview = KhataPreview(
        draft: draft,
        previousBalance: balances['previous_balance']?.toString() ?? '0.00',
        projectedBalance: balances['projected_balance']?.toString() ?? '0.00',
      );
    }
    final candidates = json['customer_candidates'] as List? ?? const [];
    return VoiceProposal(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      interpretation: json['extracted_data'] is Map
          ? Map<String, dynamic>.from(json['extracted_data'] as Map)
          : const {},
      clarification: json['clarification'] as String? ?? '',
      customerCandidates: candidates
          .whereType<Map>()
          .map(
            (row) =>
                VoiceCustomerCandidate.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      draft: draft,
      preview: preview,
    );
  }
}

class VoiceCustomerCandidate {
  const VoiceCustomerCandidate({
    required this.id,
    required this.name,
    required this.mobileNumber,
  });

  final int id;
  final String name;
  final String mobileNumber;

  factory VoiceCustomerCandidate.fromJson(Map<String, dynamic> json) =>
      VoiceCustomerCandidate(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        mobileNumber: json['mobile_number'] as String? ?? '',
      );
}

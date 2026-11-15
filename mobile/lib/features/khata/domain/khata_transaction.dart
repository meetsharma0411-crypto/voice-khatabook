class KhataDraft {
  const KhataDraft({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.transactionType,
    required this.amount,
    required this.description,
    required this.transactionDate,
    required this.status,
  });

  final int id;
  final int customerId;
  final String customerName;
  final String transactionType;
  final String amount;
  final String description;
  final String transactionDate;
  final String status;

  factory KhataDraft.fromJson(Map<String, dynamic> json) => KhataDraft(
    id: (json['id'] as num).toInt(),
    customerId: (json['customer'] as num).toInt(),
    customerName: json['customer_name'] as String? ?? '',
    transactionType: json['transaction_type'] as String? ?? '',
    amount: json['amount']?.toString() ?? '0.00',
    description: json['description'] as String? ?? '',
    transactionDate: json['transaction_date'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );
}

class KhataPreview {
  const KhataPreview({
    required this.draft,
    required this.previousBalance,
    required this.projectedBalance,
  });

  final KhataDraft draft;
  final String previousBalance;
  final String projectedBalance;

  factory KhataPreview.fromJson(Map<String, dynamic> json) => KhataPreview(
    draft: KhataDraft.fromJson(
      Map<String, dynamic>.from(json['transaction'] as Map),
    ),
    previousBalance: json['previous_balance'].toString(),
    projectedBalance: json['projected_balance'].toString(),
  );
}

class PostedKhataTransaction {
  const PostedKhataTransaction({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.amount,
    required this.transactionDate,
    required this.description,
    required this.isReversed,
  });

  final int id;
  final int customerId;
  final String customerName;
  final String type;
  final String amount;
  final String transactionDate;
  final String description;
  final bool isReversed;

  factory PostedKhataTransaction.fromJson(Map<String, dynamic> json) =>
      PostedKhataTransaction(
        id: (json['id'] as num).toInt(),
        customerId: (json['customer'] as num).toInt(),
        customerName: json['customer_name'] as String? ?? '',
        type: json['transaction_type'] as String? ?? '',
        amount: json['amount']?.toString() ?? '0.00',
        transactionDate: json['transaction_date'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isReversed: json['is_reversed'] as bool? ?? false,
      );
}

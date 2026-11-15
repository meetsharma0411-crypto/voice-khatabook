class DashboardSummary {
  const DashboardSummary({
    required this.totalCustomers,
    required this.totalUdhaar,
    required this.totalJama,
    required this.totalOutstandingBalance,
    required this.recentTransactions,
  });

  final int totalCustomers;
  final String totalUdhaar;
  final String totalJama;
  final String totalOutstandingBalance;
  final List<RecentLedgerTransaction> recentTransactions;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        totalCustomers: (json['total_customers'] as num?)?.toInt() ?? 0,
        totalUdhaar: json['total_udhaar']?.toString() ?? '0.00',
        totalJama: json['total_jama']?.toString() ?? '0.00',
        totalOutstandingBalance:
            json['total_outstanding_balance']?.toString() ?? '0.00',
        recentTransactions: ((json['recent_transactions'] as List?) ?? const [])
            .map(
              (row) => RecentLedgerTransaction.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(growable: false),
      );
}

class RecentLedgerTransaction {
  const RecentLedgerTransaction({
    required this.id,
    required this.customerName,
    required this.entryType,
    required this.transactionDate,
    required this.debitAmount,
    required this.creditAmount,
    required this.notes,
  });

  final int id;
  final String customerName;
  final String entryType;
  final String transactionDate;
  final String debitAmount;
  final String creditAmount;
  final String notes;

  factory RecentLedgerTransaction.fromJson(Map<String, dynamic> json) =>
      RecentLedgerTransaction(
        id: (json['id'] as num).toInt(),
        customerName: json['customer_name'] as String? ?? '',
        entryType: json['entry_type'] as String? ?? '',
        transactionDate: json['transaction_date'] as String? ?? '',
        debitAmount: json['debit_amount']?.toString() ?? '0.00',
        creditAmount: json['credit_amount']?.toString() ?? '0.00',
        notes: json['notes'] as String? ?? '',
      );

  String get amount {
    final debitHasValue = debitAmount
        .replaceAll(RegExp(r'[.0]'), '')
        .isNotEmpty;
    return debitHasValue ? debitAmount : creditAmount;
  }

  bool get increasesBalance =>
      debitAmount.replaceAll(RegExp(r'[.0]'), '').isNotEmpty;

  String get displayType => switch (entryType) {
    'udhaar' || 'sale' => 'Udhar',
    'jama' || 'payment' => 'Jama',
    'opening_balance' => 'Opening balance',
    'reversal' => 'Reversal',
    'adjustment' => 'Adjustment',
    _ => entryType,
  };
}

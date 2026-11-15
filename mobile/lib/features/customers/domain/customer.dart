class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.mobileNumber,
    required this.address,
    required this.notes,
    required this.isActive,
    this.currentBalance = '0.00',
  });

  final int id;
  final String name;
  final String mobileNumber;
  final String address;
  final String notes;
  final bool isActive;
  final String currentBalance;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    mobileNumber: json['mobile_number'] as String? ?? '',
    address: json['address'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    isActive: json['is_active'] as bool? ?? true,
    currentBalance: json['current_balance']?.toString() ?? '0.00',
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'mobile_number': mobileNumber,
    'address': address,
    'notes': notes,
    'is_active': isActive,
  };
}

class CustomerBalance {
  const CustomerBalance({
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.meaning,
    this.totalUdhaar = '0.00',
    this.totalJama = '0.00',
  });

  final int customerId;
  final String customerName;

  /// Kept as the server-provided decimal string. Flutter never calculates it.
  final String amount;
  final String meaning;
  final String totalUdhaar;
  final String totalJama;

  factory CustomerBalance.fromJson(Map<String, dynamic> json) =>
      CustomerBalance(
        customerId: (json['customer'] as num).toInt(),
        customerName: json['customer_name'] as String? ?? '',
        amount: json['balance']?.toString() ?? '0.00',
        meaning: json['meaning'] as String? ?? '',
        totalUdhaar: json['total_udhaar']?.toString() ?? '0.00',
        totalJama: json['total_jama']?.toString() ?? '0.00',
      );
}

class CustomerLedgerTransaction {
  const CustomerLedgerTransaction({
    required this.id,
    required this.entryType,
    required this.transactionDate,
    required this.debitAmount,
    required this.creditAmount,
    required this.notes,
    required this.isReversed,
  });

  final int id;
  final String entryType;
  final String transactionDate;
  final String debitAmount;
  final String creditAmount;
  final String notes;
  final bool isReversed;

  factory CustomerLedgerTransaction.fromJson(Map<String, dynamic> json) =>
      CustomerLedgerTransaction(
        id: (json['id'] as num).toInt(),
        entryType: json['entry_type'] as String? ?? '',
        transactionDate: json['transaction_date'] as String? ?? '',
        debitAmount: json['debit_amount']?.toString() ?? '0.00',
        creditAmount: json['credit_amount']?.toString() ?? '0.00',
        notes: json['notes'] as String? ?? '',
        isReversed: json['is_reversed'] as bool? ?? false,
      );

  String get amount {
    final debitHasValue = debitAmount
        .replaceAll(RegExp(r'[.0]'), '')
        .isNotEmpty;
    return debitHasValue ? debitAmount : creditAmount;
  }

  bool get isUdhaar => debitAmount.replaceAll(RegExp(r'[.0]'), '').isNotEmpty;

  String get displayType => switch (entryType) {
    'udhaar' || 'sale' => 'Udhar',
    'jama' || 'payment' => 'Jama',
    'opening_balance' => 'Opening balance',
    'reversal' => 'Reversal',
    'adjustment' => 'Adjustment',
    _ => entryType,
  };
}

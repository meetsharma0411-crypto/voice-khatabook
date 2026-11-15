import 'package:flutter/material.dart';

import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'customer_error_message.dart';
import 'customer_form_screen.dart';

class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({
    required this.customerId,
    required this.repository,
    super.key,
  });

  final int customerId;
  final CustomerRepository repository;

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  Customer? _customer;
  CustomerBalance? _balance;
  List<CustomerLedgerTransaction> _transactions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.get(widget.customerId),
        widget.repository.getBalance(widget.customerId),
        widget.repository.getTransactions(widget.customerId),
      ]);
      if (!mounted) return;
      setState(() {
        _customer = results[0] as Customer;
        _balance = results[1] as CustomerBalance;
        _transactions = results[2] as List<CustomerLedgerTransaction>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = customerErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final customer = _customer;
    if (customer == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          repository: widget.repository,
          customer: customer,
        ),
      ),
    );
    if (changed == true) {
      await _load();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Customer details'),
      actions: [
        IconButton(
          tooltip: 'Edit customer',
          onPressed: _customer == null ? null : _edit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _ErrorView(message: _error!, onRetry: _load)
        : _customer == null
        ? const Center(child: Text('Customer not found.'))
        : _buildDetails(_customer!, _balance),
  );

  Widget _buildDetails(Customer customer, CustomerBalance? balance) =>
      RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      customer.isActive
                          ? 'Active customer'
                          : 'Inactive customer',
                    ),
                    const Divider(height: 28),
                    _DetailRow(
                      icon: Icons.phone_outlined,
                      title: 'Mobile',
                      value: customer.mobileNumber,
                    ),
                    if (customer.address.isNotEmpty)
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        title: 'Address',
                        value: customer.address,
                      ),
                    if (customer.notes.isNotEmpty)
                      _DetailRow(
                        icon: Icons.notes_outlined,
                        title: 'Notes',
                        value: customer.notes,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outstanding balance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      balance == null
                          ? 'Balance unavailable'
                          : '₹ ${balance.amount}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (balance != null) ...[
                      const SizedBox(height: 6),
                      Text(balance.meaning),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _TotalColumn(
                              label: 'Total Udhar',
                              amount: balance.totalUdhaar,
                              color: const Color(0xFF176B45),
                            ),
                          ),
                          Expanded(
                            child: _TotalColumn(
                              label: 'Total Jama',
                              amount: balance.totalJama,
                              color: const Color(0xFF9A4D12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Transaction history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (_transactions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No posted transactions for this customer yet.'),
                ),
              )
            else
              ..._transactions.map(_CustomerTransactionTile.new),
          ],
        ),
      );
}

class _TotalColumn extends StatelessWidget {
  const _TotalColumn({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final String amount;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      Text(
        '₹ $amount',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _CustomerTransactionTile extends StatelessWidget {
  const _CustomerTransactionTile(this.transaction);
  final CustomerLedgerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final color = transaction.isUdhaar
        ? const Color(0xFF176B45)
        : const Color(0xFF9A4D12);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            transaction.isUdhaar ? Icons.call_made : Icons.call_received,
            color: color,
          ),
        ),
        title: Text(transaction.displayType),
        subtitle: Text(
          transaction.notes.isEmpty
              ? transaction.transactionDate
              : '${transaction.transactionDate} · ${transaction.notes}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹ ${transaction.amount}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            if (transaction.isReversed)
              Text('Reversed', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              Text(value),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

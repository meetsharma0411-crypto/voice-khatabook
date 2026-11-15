import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_error_message.dart';
import '../../customers/presentation/customer_picker_screen.dart';
import '../data/khata_repository.dart';
import '../domain/khata_transaction.dart';
import 'transaction_review_screen.dart';

class ManualKhataEntryScreen extends StatefulWidget {
  const ManualKhataEntryScreen({
    required this.transactionType,
    required this.customerRepository,
    required this.khataRepository,
    super.key,
  });

  final String transactionType;
  final CustomerRepository customerRepository;
  final KhataRepository khataRepository;

  @override
  State<ManualKhataEntryScreen> createState() => _ManualKhataEntryScreenState();
}

class _ManualKhataEntryScreenState extends State<ManualKhataEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  Customer? _customer;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _idempotencyKey;

  bool get _isUdhaar => widget.transactionType == 'udhaar';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  void _edited() => _idempotencyKey = null;

  String? _validateAmount(String? value) {
    final amount = value?.trim() ?? '';
    if (amount.isEmpty) return 'Enter an amount.';
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(amount)) {
      return 'Enter up to 10 whole digits and 2 decimal places.';
    }
    if (amount.replaceAll(RegExp(r'[.0]'), '').isEmpty) {
      return 'Amount must be greater than zero.';
    }
    return null;
  }

  Future<void> _chooseCustomer() async {
    final customer = await Navigator.of(context).push<Customer>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerPickerScreen(repository: widget.customerRepository),
      ),
    );
    if (customer != null && mounted) {
      setState(() {
        _customer = customer;
        _edited();
      });
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
    );
    if (selected != null) {
      setState(() {
        _date = selected;
        _edited();
      });
    }
  }

  String _dateValue(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _newIdempotencyKey() =>
      'manual-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _reviewEntry() async {
    if (!_formKey.currentState!.validate()) return;
    final customer = _customer;
    if (customer == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a customer first.')));
      return;
    }

    setState(() => _busy = true);
    KhataDraft? draft;
    try {
      _idempotencyKey ??= _newIdempotencyKey();
      draft = await widget.khataRepository.createDraft(
        customerId: customer.id,
        type: widget.transactionType,
        amount: _amount.text.trim(),
        description: _description.text.trim(),
        transactionDate: _dateValue(_date),
        idempotencyKey: _idempotencyKey!,
      );
      final preview = await widget.khataRepository.preview(draft.id);
      if (!mounted) return;
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TransactionReviewScreen(
            preview: preview,
            khataRepository: widget.khataRepository,
          ),
        ),
      );
      if (confirmed == true && mounted) {
        Navigator.of(context).pop(true);
      } else {
        _idempotencyKey = null;
      }
    } catch (error) {
      if (draft != null) {
        try {
          await widget.khataRepository.cancel(draft.id);
          _idempotencyKey = null;
        } catch (_) {
          // Leave the unposted draft available for safe retry/cancellation.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_entryError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _entryError(Object error) {
    if (error is ApiException && error.statusCode == 409) {
      return 'This entry request conflicts with an earlier request. Review the form and try again.';
    }
    return customerErrorMessage(error);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isUdhaar ? 'Add Udhar · ઉધાર' : 'Add Jama · જમા'),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_search_outlined),
              title: Text(_customer?.name ?? 'Choose customer *'),
              subtitle: Text(
                _customer?.mobileNumber ?? 'Tap to search customers',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _chooseCustomer,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amount,
            onChanged: (_) => _edited(),
            validator: _validateAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount *',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _description,
            onChanged: (_) => _edited(),
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date'),
              subtitle: Text(_dateValue(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _busy ? null : _chooseDate,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : _reviewEntry,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: Text(_busy ? 'Preparing review…' : 'Review before saving'),
          ),
        ],
      ),
    ),
  );
}

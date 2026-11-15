import 'package:flutter/material.dart';

import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'customer_error_message.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({
    required this.repository,
    super.key,
    this.customer,
  });

  final CustomerRepository repository;
  final Customer? customer;
  bool get isEditing => customer != null;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _mobile;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  final _openingBalance = TextEditingController();
  String? _openingSide;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _name = TextEditingController(text: customer?.name ?? '');
    _mobile = TextEditingController(text: customer?.mobileNumber ?? '');
    _address = TextEditingController(text: customer?.address ?? '');
    _notes = TextEditingController(text: customer?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _address.dispose();
    _notes.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  String? _validateName(String? value) =>
      value == null || value.trim().isEmpty ? 'Enter the customer name.' : null;

  String? _validateMobile(String? value) {
    final text = value?.trim() ?? '';
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) return 'Enter a mobile number.';
    if (!RegExp(r'^[0-9+() -]+$').hasMatch(text) ||
        digits.length < 7 ||
        digits.length > 15) {
      return 'Enter a valid mobile number (7–15 digits).';
    }
    return null;
  }

  String? _validateOpeningBalance(String? value) {
    if (widget.isEditing || value == null || value.trim().isEmpty) return null;
    final amount = value.trim();
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(amount)) {
      return 'Enter a valid amount with up to two decimal places.';
    }
    final isNonZero = amount.replaceAll(RegExp(r'[.0]'), '').isNotEmpty;
    if (isNonZero && _openingSide == null) {
      return 'Choose whether the customer owes you or you owe them.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final current = widget.customer;
    final customer = Customer(
      id: current?.id ?? -1,
      name: _name.text.trim(),
      mobileNumber: _mobile.text.trim(),
      address: _address.text.trim(),
      notes: _notes.text.trim(),
      isActive: current?.isActive ?? true,
    );
    try {
      if (current == null) {
        await widget.repository.create(
          customer: customer,
          openingBalanceAmount: _openingBalance.text.trim(),
          openingBalanceSide: _openingSide,
        );
      } else {
        await widget.repository.update(customer);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(customerErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isEditing ? 'Edit customer' : 'Add customer'),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _name,
            validator: _validateName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Customer name *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _mobile,
            validator: _validateMobile,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _address,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Address (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _notes,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (!widget.isEditing) ...[
            const SizedBox(height: 22),
            Text(
              'Opening balance (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text('Leave blank if this customer starts with no balance.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _openingBalance,
              validator: _validateOpeningBalance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Opening amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _openingSide,
              decoration: const InputDecoration(
                labelText: 'Opening balance side',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'debit',
                  child: Text('Customer owes the business'),
                ),
                DropdownMenuItem(
                  value: 'credit',
                  child: Text('Business owes the customer'),
                ),
              ],
              onChanged: (value) => setState(() => _openingSide = value),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save customer'),
          ),
        ],
      ),
    ),
  );
}

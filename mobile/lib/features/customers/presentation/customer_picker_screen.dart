import 'dart:async';

import 'package:flutter/material.dart';

import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'customer_error_message.dart';

class CustomerPickerScreen extends StatefulWidget {
  const CustomerPickerScreen({required this.repository, super.key});
  final CustomerRepository repository;

  @override
  State<CustomerPickerScreen> createState() => _CustomerPickerScreenState();
}

class _CustomerPickerScreenState extends State<CustomerPickerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Customer> _customers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.list(search: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _customers = rows.where((customer) => customer.isActive).toList();
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

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose customer')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              labelText: 'Search name or phone',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _customers.isEmpty
              ? const Center(child: Text('No active customers found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: _customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final customer = _customers[index];
                    return Card(
                      child: ListTile(
                        title: Text(customer.name),
                        subtitle: Text(customer.mobileNumber),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(customer),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

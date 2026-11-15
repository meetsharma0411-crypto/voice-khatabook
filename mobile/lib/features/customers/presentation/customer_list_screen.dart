import 'dart:async';

import 'package:flutter/material.dart';

import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'customer_details_screen.dart';
import 'customer_error_message.dart';
import 'customer_form_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({
    required this.repository,
    super.key,
    this.searchMode = false,
  });

  final CustomerRepository repository;
  final bool searchMode;

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Customer> _customers = const [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.list(search: _search);
      if (!mounted) return;
      setState(() {
        _customers = rows;
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search = value.trim();
      _loadCustomers();
    });
  }

  Future<void> _openAddCustomer() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(repository: widget.repository),
      ),
    );
    if (saved == true) await _loadCustomers();
  }

  Future<void> _openCustomer(Customer customer) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(
          customerId: customer.id,
          repository: widget.repository,
        ),
      ),
    );
    if (changed == true) await _loadCustomers();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.searchMode ? 'Search customers' : 'Customers'),
      actions: [
        if (!widget.searchMode)
          IconButton(
            tooltip: 'Search customers',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CustomerListScreen(
                  repository: widget.repository,
                  searchMode: true,
                ),
              ),
            ),
            icon: const Icon(Icons.search),
          ),
        IconButton(
          tooltip: 'Refresh customers',
          onPressed: _loading ? null : _loadCustomers,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: widget.searchMode
        ? null
        : FloatingActionButton.extended(
            onPressed: _openAddCustomer,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add customer'),
          ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name or mobile number',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
                icon: const Icon(Icons.close),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    ),
  );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        action: FilledButton.icon(
          onPressed: _loadCustomers,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (_customers.isEmpty) {
      final message = _search.isEmpty
          ? 'No customers yet. Add your first customer to get started.'
          : 'No customers match “$_search”.';
      return _MessageState(
        icon: Icons.people_outline,
        message: message,
        action: _search.isEmpty && !widget.searchMode
            ? FilledButton.icon(
                onPressed: _openAddCustomer,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add customer'),
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCustomers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _customers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final customer = _customers[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
                ),
              ),
              title: Text(
                customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(customer.mobileNumber),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹ ${customer.currentBalance}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => _openCustomer(customer),
            ),
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

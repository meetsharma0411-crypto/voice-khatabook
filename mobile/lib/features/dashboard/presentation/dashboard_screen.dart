import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/presentation/customer_form_screen.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_summary.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.repository,
    required this.customerRepository,
    required this.onLogout,
    required this.onAddUdhaar,
    required this.onAddJama,
    super.key,
  });

  final DashboardRepository repository;
  final CustomerRepository customerRepository;
  final VoidCallback onLogout;
  final Future<bool> Function() onAddUdhaar;
  final Future<bool> Function() onAddJama;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardSummary? _summary;
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
      final summary = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorMessage(error);
        _loading = false;
      });
    }
  }

  String _errorMessage(Object error) {
    if (error is ApiException && error.statusCode == 401) {
      return 'Your session has ended. Please sign in again.';
    }
    if (error is SocketException || error is HttpException) {
      return 'Could not reach Django. Check the server connection and try again.';
    }
    return 'Dashboard could not be loaded. Please try again.';
  }

  Future<void> _addCustomer() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerFormScreen(repository: widget.customerRepository),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _runEntry(Future<bool> Function() openEntry) async {
    if (await openEntry()) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Keshav Dairy & Beverages'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _ErrorState(message: _error!, onRetry: _load)
        : _summary == null
        ? const Center(child: Text('Dashboard is unavailable.'))
        : _buildDashboard(_summary!),
  );

  Widget _buildDashboard(DashboardSummary summary) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          'Business overview',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 720 ? 4 : 2;
            final gap = 10.0;
            final cardWidth = (width - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _StatCard(
                  width: cardWidth,
                  title: 'Customers',
                  value: summary.totalCustomers.toString(),
                  icon: Icons.people_outline,
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Total Udhar',
                  value: '₹ ${summary.totalUdhaar}',
                  icon: Icons.call_made,
                  tone: _StatTone.udhaar,
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Total Jama',
                  value: '₹ ${summary.totalJama}',
                  icon: Icons.call_received,
                  tone: _StatTone.jama,
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Outstanding balance',
                  value: '₹ ${summary.totalOutstandingBalance}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: _addCustomer,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add customer'),
            ),
            FilledButton.icon(
              onPressed: () => _runEntry(widget.onAddUdhaar),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Udhar · ઉધાર'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF176B45),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _runEntry(widget.onAddJama),
              icon: const Icon(Icons.south_west),
              label: const Text('Add Jama · જમા'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9A4D12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'Recent transactions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        if (summary.recentTransactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No posted transactions yet.'),
            ),
          )
        else
          ...summary.recentTransactions.map(_RecentTransactionTile.new),
      ],
    ),
  );
}

enum _StatTone { neutral, udhaar, jama }

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    this.tone = _StatTone.neutral,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;
  final _StatTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatTone.udhaar => const Color(0xFF176B45),
      _StatTone.jama => const Color(0xFF9A4D12),
      _StatTone.neutral => Theme.of(context).colorScheme.primary,
    };
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTransactionTile extends StatelessWidget {
  const _RecentTransactionTile(this.transaction);
  final RecentLedgerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final increases = transaction.increasesBalance;
    final color = increases ? const Color(0xFF176B45) : const Color(0xFF9A4D12);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            increases ? Icons.call_made : Icons.call_received,
            color: color,
          ),
        ),
        title: Text(transaction.customerName),
        subtitle: Text(
          '${transaction.displayType} · ${transaction.transactionDate}',
        ),
        trailing: Text(
          '₹ ${transaction.amount}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
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
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

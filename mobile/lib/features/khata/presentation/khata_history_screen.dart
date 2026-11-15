import 'package:flutter/material.dart';

import '../data/khata_repository.dart';
import '../domain/khata_transaction.dart';

class KhataHistoryScreen extends StatefulWidget {
  const KhataHistoryScreen({required this.repository, super.key});
  final KhataRepository repository;

  @override
  State<KhataHistoryScreen> createState() => _KhataHistoryScreenState();
}

class _KhataHistoryScreenState extends State<KhataHistoryScreen> {
  List<PostedKhataTransaction> _rows = const [];
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
      final rows = await widget.repository.listPosted();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Khata history could not be loaded. Check your connection and retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Khata history')),
    body: _loading
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
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : _rows.isEmpty
        ? const Center(child: Text('No posted Khata entries yet.'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _HistoryTile(_rows[index]),
            ),
          ),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.row);
  final PostedKhataTransaction row;

  @override
  Widget build(BuildContext context) {
    final udhaar = row.type == 'udhaar';
    final color = udhaar ? const Color(0xFF176B45) : const Color(0xFF9A4D12);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            udhaar ? Icons.call_made : Icons.call_received,
            color: color,
          ),
        ),
        title: Text(row.customerName),
        subtitle: Text(
          '${udhaar ? 'Udhar · ઉધાર' : 'Jama · જમા'} · ${row.transactionDate}${row.description.isEmpty ? '' : '\n${row.description}'}',
        ),
        isThreeLine: row.description.isNotEmpty,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹ ${row.amount}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            if (row.isReversed)
              Text('Reversed', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

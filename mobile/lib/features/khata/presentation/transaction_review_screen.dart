import 'package:flutter/material.dart';

import '../data/khata_repository.dart';
import '../domain/khata_transaction.dart';

class TransactionReviewScreen extends StatefulWidget {
  const TransactionReviewScreen({
    required this.preview,
    required this.khataRepository,
    this.transcript,
    super.key,
  });

  final KhataPreview preview;
  final KhataRepository khataRepository;
  final String? transcript;

  @override
  State<TransactionReviewScreen> createState() =>
      _TransactionReviewScreenState();
}

class _TransactionReviewScreenState extends State<TransactionReviewScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm and save?'),
        content: const Text(
          'Django will post this entry to the customer ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review again'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The server recalculates the final balance inside its atomic posting service.
      await widget.khataRepository.confirm(widget.preview.draft.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'The entry was not confirmed. Check your connection and retry.';
        });
      }
    }
  }

  Future<void> _cancelDraft() async {
    setState(() => _busy = true);
    try {
      await widget.khataRepository.cancel(widget.preview.draft.id);
      if (mounted) Navigator.of(context).pop(false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Could not cancel the draft. It has not changed the balance.';
        });
      }
    }
  }

  bool get _isUdhaar => widget.preview.draft.transactionType == 'udhaar';

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Review transaction')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please check these details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  _ReviewRow(
                    label: 'Customer',
                    value: preview.draft.customerName,
                  ),
                  _ReviewRow(
                    label: 'Entry type',
                    value: _isUdhaar ? 'Udhar · ઉધાર' : 'Jama · જમા',
                  ),
                  _ReviewRow(
                    label: 'Amount',
                    value: '₹ ${preview.draft.amount}',
                  ),
                  _ReviewRow(
                    label: 'Date',
                    value: preview.draft.transactionDate,
                  ),
                  if (widget.transcript != null &&
                      widget.transcript!.isNotEmpty)
                    _ReviewRow(
                      label: 'Voice transcript',
                      value: widget.transcript!,
                    ),
                  if (preview.draft.description.isNotEmpty)
                    _ReviewRow(
                      label: 'Description',
                      value: preview.draft.description,
                    ),
                  const Divider(height: 28),
                  _ReviewRow(
                    label: 'Previous balance',
                    value: '₹ ${preview.previousBalance}',
                  ),
                  _ReviewRow(
                    label: _isUdhaar ? 'New Udhar' : 'New Jama',
                    value: '₹ ${preview.draft.amount}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Projected balance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹ ${preview.projectedBalance}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _isUdhaar
                          ? const Color(0xFF176B45)
                          : const Color(0xFF9A4D12),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This preview comes from Django. The final balance is recalculated when you confirm.',
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_busy ? 'Saving…' : 'Confirm and save'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _cancelDraft,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel draft'),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

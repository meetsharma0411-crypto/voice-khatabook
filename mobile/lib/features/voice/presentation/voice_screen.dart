import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_picker_screen.dart';
import '../../khata/data/khata_repository.dart';
import '../../khata/presentation/transaction_review_screen.dart';
import '../data/voice_recorder.dart';
import '../data/voice_repository.dart';
import '../domain/voice_proposal.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    required this.customerRepository,
    required this.khataRepository,
    required this.voiceRepository,
    this.recorder,
    super.key,
  });

  final CustomerRepository customerRepository;
  final KhataRepository khataRepository;
  final VoiceRepository voiceRepository;
  final VoiceRecorder? recorder;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  late final VoiceRecorder _recorder = widget.recorder ?? DeviceVoiceRecorder();
  Customer? _customer;
  String? _audioPath;
  String? _idempotencyKey;
  VoiceProposal? _proposal;
  bool _recording = false;
  bool _busy = false;
  String? _error;
  Timer? _recordingLimit;

  @override
  void dispose() {
    _recordingLimit?.cancel();
    _recorder.dispose();
    final path = _audioPath;
    if (path != null) {
      unawaited(File(path).delete().then<void>((_) {}, onError: (Object _) {}));
    }
    super.dispose();
  }

  Future<void> _chooseCustomer() async {
    final customer = await Navigator.of(context).push<Customer>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerPickerScreen(repository: widget.customerRepository),
      ),
    );
    if (customer != null && mounted) setState(() => _customer = customer);
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_recording) {
      await _stopRecording();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        setState(
          () => _error =
              'Allow microphone access in Android settings to record a voice entry.',
        );
        return;
      }
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'keshav_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(path);
      if (!mounted) return;
      setState(() {
        _audioPath = null;
        _proposal = null;
        _idempotencyKey = _newKey();
        _error = null;
        _recording = true;
      });
      _recordingLimit = Timer(const Duration(seconds: 60), _stopRecording);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Recording could not start. Check microphone access and try again.',
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordingLimit?.cancel();
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _audioPath = path;
        _error = path == null
            ? 'No recording was captured. Please try again.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'The recording could not be completed. Please try again.';
        });
      }
    }
  }

  String _newKey() =>
      'voice-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _submit() async {
    final path = _audioPath;
    if (path == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _proposal = null;
    });
    try {
      final proposal = await widget.voiceRepository.createProposal(
        audioPath: path,
        customerId: _customer?.id,
        idempotencyKey: _idempotencyKey ??= _newKey(),
      );
      if (!mounted) return;
      await _handleProposal(proposal);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseClarifiedCustomer() async {
    final proposal = _proposal;
    if (proposal == null || !proposal.needsCustomer || _busy) return;
    final customer = await Navigator.of(context).push<Customer>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerPickerScreen(repository: widget.customerRepository),
      ),
    );
    if (customer == null || !mounted) return;
    setState(() {
      _customer = customer;
      _busy = true;
      _error = null;
    });
    try {
      final resolved = await widget.voiceRepository.resolveCustomer(
        proposalId: proposal.id,
        customerId: customer.id,
      );
      if (mounted) await _handleProposal(resolved);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleProposal(VoiceProposal proposal) async {
    if (!mounted) return;
    setState(() => _proposal = proposal);
    if (proposal.readyForReview) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TransactionReviewScreen(
            preview: proposal.preview!,
            khataRepository: widget.khataRepository,
            transcript: proposal.transcript,
          ),
        ),
      );
      if (saved == true && mounted) Navigator.of(context).pop(true);
    }
  }

  String _errorMessage(Object error) {
    if (error is ApiException && error.statusCode == 401) {
      return 'Your session has ended. Please sign in again.';
    }
    if (error is ApiException && error.statusCode == 413) {
      return 'This recording is too large. Record a shorter instruction.';
    }
    if (error is ApiException && error.statusCode == 503) {
      return 'Gemini is not configured on the Django server yet.';
    }
    if (error is ApiException && error.statusCode == 502) {
      return 'Gemini could not understand this recording. Try speaking clearly and again.';
    }
    return 'Voice request failed. Check your connection and retry.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Voice Khata')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_search_outlined),
            title: Text(_customer?.name ?? 'Choose a customer (optional)'),
            subtitle: Text(
              _customer?.mobileNumber ??
                  'Or say the customer name in your recording',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _chooseCustomer,
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Icon(
                  _recording ? Icons.mic : Icons.mic_none,
                  size: 50,
                  color: _recording
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  _recording
                      ? 'Recording… up to 60 seconds'
                      : 'Speak in Gujarati, Hindi, English, or Hinglish',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                  label: Text(
                    _recording ? 'Stop recording' : 'Start recording',
                  ),
                ),
                if (_audioPath != null && !_recording) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Recording ready to send to Django for transcription.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _busy ? 'Understanding voice…' : 'Transcribe and review',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Audio is sent to Django and Gemini for processing. The app keeps the transcript and draft for review; it never posts a ledger entry automatically.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_proposal != null) ...[
          const SizedBox(height: 14),
          _ProposalResult(
            proposal: _proposal!,
            busy: _busy,
            onChooseCustomer: _chooseClarifiedCustomer,
          ),
        ],
      ],
    ),
  );
}

class _ProposalResult extends StatelessWidget {
  const _ProposalResult({
    required this.proposal,
    required this.busy,
    required this.onChooseCustomer,
  });
  final VoiceProposal proposal;
  final bool busy;
  final VoidCallback onChooseCustomer;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transcript', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          SelectableText(
            proposal.transcript.isEmpty
                ? 'No transcript available.'
                : proposal.transcript,
          ),
          if (proposal.clarification.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              proposal.clarification,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (proposal.needsCustomer) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onChooseCustomer,
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('Choose the correct customer'),
            ),
          ],
          if (proposal.status == 'needs_clarification') ...[
            const SizedBox(height: 8),
            const Text(
              'No ledger draft was created. Correct the product/rate or record a clearer instruction.',
            ),
          ],
          if (proposal.status == 'processing')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This request is still processing. Retry with the same recording shortly.',
              ),
            ),
        ],
      ),
    ),
  );
}

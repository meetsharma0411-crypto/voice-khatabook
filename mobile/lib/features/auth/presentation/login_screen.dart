import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authRepository,
    required this.onLogin,
    this.message,
    super.key,
  });

  final AuthRepository authRepository;
  final VoidCallback onLogin;
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authRepository.login(
        username: _username.text.trim(),
        password: _password.text,
      );
      _password.clear();
      widget.onLogin();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _loginError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _loginError(Object error) {
    if (error is ApiException && error.statusCode == 400) {
      final body = error.body;
      if (body is Map) {
        final details = body.entries.map((entry) {
          final value = entry.value;
          final message = value is List ? value.join(' ') : value.toString();
          return '${entry.key}: $message';
        }).join('\n');
        if (details.isNotEmpty) return details;
      }
      if (body is String && body.trim().isNotEmpty) return body.trim();
      return 'The server rejected the login request. Check the username and password.';
    }
    if (error is ApiException && error.statusCode == 401) {
      return 'Username or password is incorrect.';
    }
    if (error is ApiException && error.statusCode == 429) {
      return 'Too many login attempts. Wait a minute and try again.';
    }
    if (error is ApiException) {
      return 'Sign in failed (HTTP ${error.statusCode}).';
    }
    return 'Could not sign in. Check the server connection and try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Keshav Dairy & Beverages',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to KhataBook',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _username,
                    enabled: !_submitting,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your username.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    enabled: !_submitting,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your password.'
                        : null,
                  ),
                  if (_error != null || widget.message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error ?? widget.message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

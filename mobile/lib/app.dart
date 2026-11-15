import 'package:flutter/material.dart';

import 'core/auth/auth_token_store.dart';
import 'core/config/api_config.dart';
import 'core/navigation/app_shell.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/customers/data/customer_repository.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/khata/data/khata_repository.dart';
import 'features/voice/data/voice_repository.dart';

class KeshavKhataApp extends StatefulWidget {
  const KeshavKhataApp({
    super.key,
    this.customerRepository,
    this.dashboardRepository,
    this.khataRepository,
    this.authTokenStore,
  });

  final CustomerRepository? customerRepository;
  final DashboardRepository? dashboardRepository;
  final KhataRepository? khataRepository;
  final AuthTokenStore? authTokenStore;

  @override
  State<KeshavKhataApp> createState() => _KeshavKhataAppState();
}

class _KeshavKhataAppState extends State<KeshavKhataApp> {
  late final AuthTokenStore _tokenStore;
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final CustomerRepository _customerRepository;
  late final DashboardRepository _dashboardRepository;
  late final KhataRepository _khataRepository;
  late final VoiceRepository _voiceRepository;
  bool _restoring = true;
  bool _authenticated = false;
  String? _authNotice;

  @override
  void initState() {
    super.initState();
    _tokenStore =
        widget.authTokenStore ??
        SecureAuthTokenStore(storage: FlutterSecureKeyValueStorage());
    _apiClient = ApiClient(
      baseUrl: ApiConfig.baseUrl,
      tokenStore: _tokenStore,
      onUnauthenticated: _onUnauthenticated,
    );
    _authRepository = AuthRepository(
      apiClient: _apiClient,
      tokenStore: _tokenStore,
    );
    _customerRepository =
        widget.customerRepository ?? CustomerRepository(_apiClient);
    _dashboardRepository =
        widget.dashboardRepository ?? DashboardRepository(_apiClient);
    _khataRepository = widget.khataRepository ?? KhataRepository(_apiClient);
    _voiceRepository = VoiceRepository(_apiClient);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final tokens = await _tokenStore.readTokens();
      if (!mounted) return;
      setState(() {
        _authenticated =
            tokens != null &&
            tokens.access.isNotEmpty &&
            tokens.refresh.isNotEmpty;
        _restoring = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authenticated = false;
        _restoring = false;
      });
    }
  }

  void _onLogin() {
    if (mounted) {
      setState(() {
        _authenticated = true;
        _authNotice = null;
      });
    }
  }

  void _onUnauthenticated() {
    if (mounted && _authenticated) setState(() => _authenticated = false);
  }

  Future<void> _logout() async {
    try {
      await _authRepository.logout();
    } catch (_) {
      if (mounted) {
        setState(
          () => _authNotice =
              'This device was signed out, but server token revocation could not be confirmed. Check your connection and sign in again.',
        );
      }
    }
    if (mounted) setState(() => _authenticated = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keshav Dairy KhataBook',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: _restoring
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _authenticated
        ? AppShell(
            customerRepository: _customerRepository,
            dashboardRepository: _dashboardRepository,
            khataRepository: _khataRepository,
            voiceRepository: _voiceRepository,
            onLogout: _logout,
          )
        : LoginScreen(
            authRepository: _authRepository,
            onLogin: _onLogin,
            message: _authNotice,
          ),
  );
}

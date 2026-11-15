import 'package:flutter/material.dart';

import '../../features/customers/data/customer_repository.dart';
import '../../features/customers/presentation/customer_list_screen.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/khata/data/khata_repository.dart';
import '../../features/khata/presentation/manual_khata_entry_screen.dart';
import '../../features/khata/presentation/khata_history_screen.dart';
import '../../features/shared/presentation/profile_screen.dart';
import '../../features/voice/data/voice_repository.dart';
import '../../features/voice/presentation/voice_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.customerRepository,
    required this.dashboardRepository,
    required this.khataRepository,
    required this.voiceRepository,
    required this.onLogout,
    super.key,
  });

  final CustomerRepository customerRepository;
  final DashboardRepository dashboardRepository;
  final KhataRepository khataRepository;
  final VoiceRepository voiceRepository;
  final VoidCallback onLogout;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: switch (_index) {
        0 => DashboardScreen(
          repository: widget.dashboardRepository,
          customerRepository: widget.customerRepository,
          onLogout: widget.onLogout,
          onAddUdhaar: () => _openEntry('udhaar'),
          onAddJama: () => _openEntry('jama'),
        ),
        1 => CustomerListScreen(repository: widget.customerRepository),
        2 => KhataHistoryScreen(repository: widget.khataRepository),
        3 => VoiceScreen(
          customerRepository: widget.customerRepository,
          khataRepository: widget.khataRepository,
          voiceRepository: widget.voiceRepository,
        ),
        _ => ProfileScreen(onLogout: widget.onLogout),
      },
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          label: 'Customers',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          label: 'Khata',
        ),
        NavigationDestination(icon: Icon(Icons.mic_none), label: 'Voice'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );

  Future<bool> _openEntry(String type) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualKhataEntryScreen(
          transactionType: type,
          customerRepository: widget.customerRepository,
          khataRepository: widget.khataRepository,
        ),
      ),
    );
    return saved == true;
  }
}

import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onLogout, super.key});
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Keshav Dairy & Beverages'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: onLogout,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 56),
            SizedBox(height: 16),
            Text(
              'Welcome to Keshav KhataBook',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('Your customer khata tools will appear here.'),
          ],
        ),
      ),
    ),
  );
}

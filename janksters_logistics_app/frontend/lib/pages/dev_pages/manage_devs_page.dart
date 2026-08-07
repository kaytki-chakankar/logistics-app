import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ManageDevsPage extends StatefulWidget {
  const ManageDevsPage({super.key});

  @override
  State<ManageDevsPage> createState() => _ManageDevsPageState();
}

class _ManageDevsPageState extends State<ManageDevsPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);
  final _emailController = TextEditingController();
  List<String> _developers = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevelopers();
  }

  Future<void> _loadDevelopers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse('$_baseUrl/developers'));
      if (response.statusCode != 200) throw Exception();
      final data = jsonDecode(response.body);
      if (mounted) {
        setState(() {
          _developers = (data['developers'] as List<dynamic>? ?? [])
              .map((email) => email.toString())
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load developers.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addDeveloper() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/developers'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 201) {
        setState(() {
          _developers = (data['developers'] as List<dynamic>).map((item) => item.toString()).toList();
          _emailController.clear();
        });
      } else {
        _showMessage(data['error'] ?? 'Unable to add developer.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to add developer.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeDeveloper(String email) async {
    setState(() => _isSaving = true);
    try {
      final response = await http.delete(Uri.parse('$_baseUrl/developers/${Uri.encodeComponent(email)}'));
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _developers = (data['developers'] as List<dynamic>).map((item) => item.toString()).toList());
      } else {
        _showMessage(data['error'] ?? 'Unable to remove developer.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to remove developer.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Poppins'))),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryRed,
        title: const Text('Manage Devs', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _isLoading ? null : _loadDevelopers, icon: const Icon(Icons.refresh))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Developer Access', style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.bold, color: _accentRed)),
            const SizedBox(height: 6),
            const Text('People on this list can open Developer Tools.', style: TextStyle(fontFamily: 'Poppins')),
            const SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Developer email', labelStyle: TextStyle(fontFamily: 'Poppins')),
                        onSubmitted: (_) => _isSaving ? null : _addDeveloper(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _addDeveloper,
                      style: ElevatedButton.styleFrom(backgroundColor: _primaryRed, foregroundColor: Colors.white),
                      child: const Text('Add', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: _primaryRed)))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!, style: const TextStyle(fontFamily: 'Poppins'))))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _developers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final email = _developers[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: _primaryRed.withOpacity(0.12), child: const Icon(Icons.person, color: _primaryRed)),
                        title: Text(email, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        trailing: IconButton(
                          tooltip: 'Remove developer',
                          onPressed: _isSaving ? null : () => _removeDeveloper(email),
                          icon: const Icon(Icons.delete_outline, color: _primaryRed),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

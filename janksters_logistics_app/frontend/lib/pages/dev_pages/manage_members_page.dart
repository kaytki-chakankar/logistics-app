import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ManageMembersPage extends StatefulWidget {
  const ManageMembersPage({super.key});

  @override
  State<ManageMembersPage> createState() => _ManageMembersPageState();
}

class _ManageMembersPageState extends State<ManageMembersPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);
  final _memberEmailController = TextEditingController();
  final _developerEmailController = TextEditingController();
  final _memberSearchController = TextEditingController();
  final _developerSearchController = TextEditingController();
  List<String> _members = [];
  List<String> _developers = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPeople();
    _memberSearchController.addListener(() => setState(() {}));
    _developerSearchController.addListener(() => setState(() {}));
  }

  Future<void> _loadPeople() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/members')),
        http.get(Uri.parse('$_baseUrl/developers')),
      ]);
      if (responses.any((response) => response.statusCode != 200)) throw Exception();
      final memberData = jsonDecode(responses[0].body);
      final developerData = jsonDecode(responses[1].body);
      if (mounted) {
        setState(() {
          _members = List<String>.from(memberData['members'] ?? []);
          _developers = List<String>.from(developerData['developers'] ?? []);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load members.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _add(String endpoint, TextEditingController controller) async {
    final email = controller.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 201) {
        controller.clear();
        await _loadPeople();
      } else {
        _showMessage(data['error'] ?? 'Unable to add email.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to add email.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _remove(String endpoint, String email) async {
    setState(() => _isSaving = true);
    try {
      final response = await http.delete(Uri.parse('$_baseUrl/$endpoint/${Uri.encodeComponent(email)}'));
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        await _loadPeople();
      } else {
        _showMessage(data['error'] ?? 'Unable to remove email.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to remove email.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Poppins'))));
  }

  List<String> _filtered(List<String> people, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    return normalizedQuery.isEmpty ? people : people.where((email) => email.contains(normalizedQuery)).toList();
  }

  Widget _peopleTab({
    required String emptyLabel,
    required String endpoint,
    required String fieldLabel,
    required String intro,
    required IconData icon,
    required List<String> people,
    required TextEditingController emailController,
    required TextEditingController searchController,
  }) {
    final visiblePeople = _filtered(people, searchController.text);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(intro, style: const TextStyle(fontFamily: 'Poppins', color: _accentRed, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: fieldLabel, labelStyle: const TextStyle(fontFamily: 'Poppins')),
                  onSubmitted: (_) => _isSaving ? null : _add(endpoint, emailController),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isSaving ? null : () => _add(endpoint, emailController),
                style: ElevatedButton.styleFrom(backgroundColor: _primaryRed, foregroundColor: Colors.white),
                child: const Text('Add', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by email',
              hintStyle: TextStyle(fontFamily: 'Poppins'),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('${visiblePeople.length} of ${people.length}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Expanded(
            child: visiblePeople.isEmpty
                ? Center(child: Text(emptyLabel, style: const TextStyle(fontFamily: 'Poppins')))
                : ListView.separated(
                    itemCount: visiblePeople.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final email = visiblePeople[index];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(icon, size: 20, color: _primaryRed),
                        title: Text(email, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                        trailing: IconButton(
                          tooltip: endpoint == 'members' ? 'Remove from active members' : 'Remove developer access',
                          onPressed: _isSaving ? null : () => _remove(endpoint, email),
                          icon: const Icon(Icons.remove_circle_outline, color: _primaryRed),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _memberEmailController.dispose();
    _developerEmailController.dispose();
    _memberSearchController.dispose();
    _developerSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _primaryRed,
          title: const Text('Manage Members', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          actions: [IconButton(onPressed: _isLoading ? null : _loadPeople, icon: const Icon(Icons.refresh))],
          bottom: const TabBar(
            labelStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
            tabs: [Tab(text: 'Regular Members'), Tab(text: 'Developers')],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _primaryRed))
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(fontFamily: 'Poppins')))
                : TabBarView(
                    children: [
                      _peopleTab(
                        emptyLabel: 'No regular members found.',
                        endpoint: 'members',
                        fieldLabel: 'Member email',
                        intro: 'Active members receive attendance records for new meetings.',
                        icon: Icons.person_outline,
                        people: _members,
                        emailController: _memberEmailController,
                        searchController: _memberSearchController,
                      ),
                      _peopleTab(
                        emptyLabel: 'No developers found.',
                        endpoint: 'developers',
                        fieldLabel: 'Developer email',
                        intro: 'Developers can open Developer Tools.',
                        icon: Icons.admin_panel_settings_outlined,
                        people: _developers,
                        emailController: _developerEmailController,
                        searchController: _developerSearchController,
                      ),
                    ],
                  ),
      ),
    );
  }
}

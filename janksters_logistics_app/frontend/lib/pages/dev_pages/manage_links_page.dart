import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ManageLinksPage extends StatefulWidget {
  const ManageLinksPage({super.key});

  @override
  State<ManageLinksPage> createState() => _ManageLinksPageState();
}

class _ManageLinksPageState extends State<ManageLinksPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final List<Map<String, String>> _links = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/important-links'));
      if (response.statusCode != 200) throw Exception('Unable to load links.');
      final data = jsonDecode(response.body);
      final links = (data['links'] as List<dynamic>? ?? [])
          .map<Map<String, String>>(
            (link) => {
              'title': link['title'].toString(),
              'url': link['url'].toString(),
            },
          )
          .toList();
      if (mounted) {
        setState(() {
          _links
            ..clear()
            ..addAll(links);
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load links.';
          _loading = false;
        });
      }
    }
  }

  void _message(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: isError
            ? const Color(0xFF6C1016)
            : const Color(0xFFE30F13),
      ),
    );
  }

  Future<void> _addLink() async {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();
    if (title.isEmpty || url.isEmpty) {
      _message('Enter both a title and a URL.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/important-links'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title, 'url': url}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 201)
        throw Exception(data['error'] ?? 'Unable to add link.');
      _titleController.clear();
      _urlController.clear();
      await _loadLinks();
      if (mounted) _message('Link added to the live Links page.');
    } catch (error) {
      if (mounted)
        _message(
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeLink(int index) async {
    final title = _links[index]['title'] ?? 'this link';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Remove link?',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        content: Text(
          'Are you sure you want to remove “$title” from the Links page?',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/important-links/$index'),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200)
        throw Exception(data['error'] ?? 'Unable to remove link.');
      await _loadLinks();
      if (mounted) _message('Link removed from the live Links page.');
    } catch (error) {
      if (mounted)
        _message(
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFE30F13);
    const accentRed = Color(0xFF6C1016);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Links',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLinks,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Important Links',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: accentRed,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add or remove the links members see on the Links page. Changes are live immediately.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Link title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saving ? null : _addLink(),
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      hintText: 'https://example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _addLink,
                    icon: const Icon(Icons.add_link),
                    label: const Text(
                      'Add link',
                      style: TextStyle(fontFamily: 'Poppins'),
                    ),
                    style: FilledButton.styleFrom(backgroundColor: primaryRed),
                  ),
                  const SizedBox(height: 28),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: accentRed,
                      ),
                    )
                  else if (_links.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'No links have been added.',
                          style: TextStyle(fontFamily: 'Poppins'),
                        ),
                      ),
                    )
                  else
                    ..._links.asMap().entries.map((entry) {
                      final index = entry.key;
                      final link = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.link, color: primaryRed),
                          title: Text(
                            link['title'] ?? '',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            link['url'] ?? '',
                            style: const TextStyle(fontFamily: 'Poppins'),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Remove link',
                            color: accentRed,
                            onPressed: _saving
                                ? null
                                : () => _removeLink(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

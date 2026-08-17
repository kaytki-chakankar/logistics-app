import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ManageSeasonsPage extends StatefulWidget {
  const ManageSeasonsPage({super.key});

  @override
  State<ManageSeasonsPage> createState() => _ManageSeasonsPageState();
}

class _ManageSeasonsPageState extends State<ManageSeasonsPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);
  final _nameController = TextEditingController();
  final _fullSemesterHoursController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadFullSemesterHours();
  }

  Future<void> _loadFullSemesterHours() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/attendance/settings/full-semester-hours'),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (mounted) {
        _fullSemesterHoursController.text =
            (data['fullSemesterRequiredHours'] as num?)?.toString() ?? '235';
      }
    } catch (_) {
      // The field keeps its blank state if the setting cannot be loaded.
    }
  }

  Future<void> _saveFullSemesterHours() async {
    final hours = double.tryParse(_fullSemesterHoursController.text.trim());
    if (hours == null || hours <= 0) {
      _showMessage('Enter a required-hours value greater than zero.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/attendance/settings/full-semester-hours'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fullSemesterRequiredHours': hours}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        _fullSemesterHoursController.text =
            (data['fullSemesterRequiredHours'] as num?)?.toString() ??
            hours.toString();
        _showMessage('Full-semester requirement saved.');
      } else {
        _showMessage(data['error'] ?? 'Unable to save required hours.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to save required hours.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _archiveSeason() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a name for the completed season.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Archive this season?',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        content: Text(
          '“$name” will be saved as read-only history. The current build attendance will reset, while every current member stays as an empty record.',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Archive & Reset',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/attendance/seasons/archive'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 201) {
        _nameController.clear();
        _showMessage(
          '${data['season']['name']} was saved. The new build season is ready.',
        );
      } else {
        _showMessage(data['error'] ?? 'Unable to archive the season.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to archive the season.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Poppins')),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fullSemesterHoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryRed,
        title: const Text(
          'Manage Seasons',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Full-semester requirement',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _accentRed,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Used by the Full Semester attendance circle and the calculator.',
              style: TextStyle(fontFamily: 'Poppins', height: 1.45),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fullSemesterHoursController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Required hours',
                      border: OutlineInputBorder(),
                      labelStyle: TextStyle(fontFamily: 'Poppins'),
                    ),
                    style: const TextStyle(fontFamily: 'Poppins'),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveFullSemesterHours,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryRed,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Finish the current build season',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _accentRed,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This saves the editable attendance master as history, then starts a fresh editable master. Current members remain; only their meeting records reset.',
              style: TextStyle(fontFamily: 'Poppins', height: 1.45),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Completed season name',
                hintText: 'Example: Build Season 2026',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(fontFamily: 'Poppins'),
                hintStyle: TextStyle(fontFamily: 'Poppins'),
              ),
              style: const TextStyle(fontFamily: 'Poppins'),
              onSubmitted: (_) => _isSaving ? null : _archiveSeason(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSaving ? null : _archiveSeason,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.archive_outlined),
                label: const Text(
                  'Archive Current Season & Start Fresh',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

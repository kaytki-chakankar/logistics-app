import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ManageAdjustmentDatesPage extends StatefulWidget {
  const ManageAdjustmentDatesPage({super.key});

  @override
  State<ManageAdjustmentDatesPage> createState() => _ManageAdjustmentDatesPageState();
}

class _ManageAdjustmentDatesPageState extends State<ManageAdjustmentDatesPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);
  DateTime? _selectedDate;
  List<String> _closedDates = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  Future<void> _loadSettings() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse('$_baseUrl/attendance/adjustments/settings'));
      if (response.statusCode != 200) throw Exception();
      final data = jsonDecode(response.body);
      if (mounted) setState(() => _closedDates = List<String>.from(data['closedDates'] ?? []));
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load adjustment date settings.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected != null && mounted) setState(() => _selectedDate = selected);
  }

  Future<void> _setDateOpen(String date, bool isOpen) async {
    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/attendance/adjustments/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'date': date, 'isOpen': isOpen}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _closedDates = List<String>.from(data['closedDates'] ?? []);
          if (!isOpen) _selectedDate = null;
        });
      } else {
        _showMessage(data['error'] ?? 'Unable to update this date.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to update this date.');
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryRed,
        title: const Text('Manage Adjustment Dates', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Adjustment Availability', style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.bold, color: _accentRed)),
            const SizedBox(height: 6),
            const Text('All dates are open by default. Close a date to stop new attendance adjustment requests.', style: TextStyle(fontFamily: 'Poppins')),
            const SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_selectedDate == null ? 'Choose a date' : _formatDate(_selectedDate!), style: const TextStyle(fontFamily: 'Poppins')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _selectedDate == null || _isSaving ? null : () => _setDateOpen(_formatDate(_selectedDate!), false),
                      style: ElevatedButton.styleFrom(backgroundColor: _primaryRed, foregroundColor: Colors.white),
                      child: const Text('Close date', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Closed dates', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: _accentRed)),
            const SizedBox(height: 8),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: _primaryRed)))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!, style: const TextStyle(fontFamily: 'Poppins'))))
            else if (_closedDates.isEmpty)
              const Expanded(child: Center(child: Text('No dates are closed.', style: TextStyle(fontFamily: 'Poppins'))))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _closedDates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final date = _closedDates[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_busy, color: _primaryRed),
                        title: Text(date, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        subtitle: const Text('Adjustment requests are closed', style: TextStyle(fontFamily: 'Poppins')),
                        trailing: OutlinedButton(
                          onPressed: _isSaving ? null : () => _setDateOpen(date, true),
                          style: OutlinedButton.styleFrom(foregroundColor: _primaryRed, side: const BorderSide(color: _primaryRed)),
                          child: const Text('Reopen', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
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

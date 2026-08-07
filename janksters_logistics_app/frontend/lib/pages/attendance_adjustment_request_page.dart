import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AttendanceAdjustmentRequestPage extends StatefulWidget {
  const AttendanceAdjustmentRequestPage({required this.date, super.key});

  final String date;

  @override
  State<AttendanceAdjustmentRequestPage> createState() =>
      _AttendanceAdjustmentRequestPageState();
}

class _AttendanceAdjustmentRequestPageState
    extends State<AttendanceAdjustmentRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController();
  TimeOfDay? _arrivalTime;
  TimeOfDay? _departureTime;
  bool _isSubmitting = false;

  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Select time';
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> _pickTime(bool isArrival) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isArrival
          ? (_arrivalTime ?? TimeOfDay.now())
          : (_departureTime ?? TimeOfDay.now()),
    );
    if (selected != null && mounted) {
      setState(() {
        if (isArrival) _arrivalTime = selected;
        else _departureTime = selected;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_arrivalTime == null || _departureTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both arrival and departure times.')),
      );
      return;
    }
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/attendance/adjustments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'date': widget.date,
          'arrivalTime': _formatTime(_arrivalTime),
          'departureTime': _formatTime(_departureTime),
          'hoursHere': double.parse(_hoursController.text.trim()),
        }),
      );
      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adjustment request submitted for review.')),
        );
        Navigator.pop(context);
      } else {
        final body = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] ?? 'Unable to submit request.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to submit request. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryRed,
        title: const Text(
          'Adjust Attendance',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Request an adjustment for ${widget.date}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _accentRed,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your request will be reviewed by a developer before attendance is changed.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('What time did you arrive?', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                      subtitle: Text(_formatTime(_arrivalTime), style: const TextStyle(fontFamily: 'Poppins')),
                      trailing: const Icon(Icons.schedule, color: _primaryRed),
                      onTap: () => _pickTime(true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('What time did you leave?', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                      subtitle: Text(_formatTime(_departureTime), style: const TextStyle(fontFamily: 'Poppins')),
                      trailing: const Icon(Icons.schedule, color: _primaryRed),
                      onTap: () => _pickTime(false),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hoursController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'How many hours were you there?',
                        labelStyle: TextStyle(fontFamily: 'Poppins'),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final hours = double.tryParse(value?.trim() ?? '');
                        if (hours == null || hours < 0 || hours > 24) {
                          return 'Enter a number of hours from 0 to 24.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator())
                            : const Text('Submit request'),
                      ),
                    ),
                    ],
                  ),
                ),
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

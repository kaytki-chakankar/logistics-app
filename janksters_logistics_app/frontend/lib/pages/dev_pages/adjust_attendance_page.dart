import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'manage_adjustment_dates_page.dart';

class AdjustAttendancePage extends StatefulWidget {
  const AdjustAttendancePage({super.key});

  @override
  State<AdjustAttendancePage> createState() => _AdjustAttendancePageState();
}

class _AdjustAttendancePageState extends State<AdjustAttendancePage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);
  List<dynamic> _adjustments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAdjustments();
  }

  Future<void> _loadAdjustments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse('$_baseUrl/attendance/adjustments'));
      if (response.statusCode != 200) throw Exception('Unable to load requests');
      final data = jsonDecode(response.body);
      if (mounted) setState(() => _adjustments = data['adjustments'] ?? []);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load adjustment requests.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolve(Map<String, dynamic> request, String status) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/attendance/adjustments/${request['id']}/resolve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved' ? 'Attendance updated.' : 'Request rejected.',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
          ),
        );
        await _loadAdjustments();
      } else {
        final body = jsonDecode(response.body);
        setState(() => _error = body['error'] ?? 'Unable to resolve request.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to resolve request.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: _accentRed,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _previousAttendance(Map<String, dynamic> request) {
    final previous = Map<String, dynamic>.from(request['previousAttendance'] ?? {});
    final status = previous['status'] ?? 'missing';
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String detail;
    if (status == 'flagged') {
      icon = Icons.warning_amber_rounded;
      color = _primaryRed;
      title = 'Flagged entry';
      detail = previous['reason'] ?? 'Flagged entry';
    } else if (status == 'absent') {
      icon = Icons.cancel_outlined;
      color = Colors.grey.shade700;
      title = 'Absent';
      detail = '0.00 hours recorded';
    } else if (status == 'attended') {
      icon = Icons.check_circle_outline;
      color = _accentRed;
      title = 'Attended';
      final hours = (previous['hours'] as num?)?.toDouble() ?? 0;
      detail = '${hours.toStringAsFixed(2)} hours recorded';
    } else {
      icon = Icons.help_outline;
      color = Colors.grey.shade700;
      title = 'No record found';
      detail = 'No attendance entry exists for this date.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: color)),
                Text(detail, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryRed,
        title: const Text('Adjust Attendance', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageAdjustmentDatesPage()),
              );
            },
            icon: const Icon(Icons.event_busy),
            tooltip: 'Manage adjustment dates',
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadAdjustments,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh requests',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryRed))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(fontFamily: 'Poppins')))
              : _adjustments.isEmpty
                  ? const Center(child: Text('No adjustment requests yet.', style: TextStyle(fontFamily: 'Poppins')))
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _adjustments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final request = Map<String, dynamic>.from(_adjustments[index]);
                        final pending = request['status'] == 'pending';
                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(request['email'] ?? '', style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.bold))),
                                    _StatusChip(status: (request['status'] ?? 'pending').toString()),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text('Date: ${request['date']}', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                                const Divider(height: 28),
                                _sectionLabel('CURRENT ATTENDANCE RECORD'),
                                _previousAttendance(request),
                                const SizedBox(height: 16),
                                _sectionLabel('REQUESTED CORRECTION'),
                                Text('Arrival: ${request['arrivalTime']}', style: const TextStyle(fontFamily: 'Poppins')),
                                Text('Departure: ${request['departureTime']}', style: const TextStyle(fontFamily: 'Poppins')),
                                Text('Requested hours: ${request['hoursHere']}', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                                if (pending) ...[
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () => _resolve(request, 'rejected'),
                                          style: OutlinedButton.styleFrom(foregroundColor: _primaryRed, side: const BorderSide(color: _primaryRed), padding: const EdgeInsets.symmetric(vertical: 12)),
                                          child: const Text('Reject', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () => _resolve(request, 'approved'),
                                          style: ElevatedButton.styleFrom(backgroundColor: _primaryRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                                          child: const Text('Approve & update', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final pending = status == 'pending';
    final color = pending ? const Color(0xFFE6A700) : const Color(0xFF6C1016);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(), style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

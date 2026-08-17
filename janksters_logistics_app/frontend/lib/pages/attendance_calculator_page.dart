import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AttendanceCalculatorPage extends StatefulWidget {
  const AttendanceCalculatorPage({super.key});

  @override
  State<AttendanceCalculatorPage> createState() =>
      _AttendanceCalculatorPageState();
}

class _AttendanceCalculatorPageState extends State<AttendanceCalculatorPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  static const _accentRed = Color(0xFF6C1016);
  final Map<String, TextEditingController> _hoursControllers = {};
  List<Map<String, dynamic>> _calendar = [];
  List<dynamic> _attendance = [];
  double _currentTotalHours = 0;
  double _fullSemesterRequiredHours = 235;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCalculator();
  }

  DateTime? _date(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return DateTime.tryParse(value);
    return DateTime.tryParse(
      '${parts[2]}-${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}',
    );
  }

  bool _isPastOrToday(String date) {
    final meetingDate = _date(date);
    if (meetingDate == null) return false;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return !meetingDate.isAfter(startOfToday);
  }

  double _actualHoursForDate(String date) {
    for (final item in _attendance) {
      if (item['date']?.toString().split(' ').first == date) {
        if (item['error'] == true || item['error']?.toString() == 'true')
          return 0;
        return (item['durationHours'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  Future<void> _loadCalculator() async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email == null) {
      setState(() {
        _loading = false;
        _error = 'No user email found.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/attendance/calendar')),
        http.get(Uri.parse('$_baseUrl/attendance/$email')),
      ]);
      if (responses.any((response) => response.statusCode != 200))
        throw Exception();
      final calendarData = jsonDecode(responses[0].body);
      final attendanceData = jsonDecode(responses[1].body);
      final calendar = List<dynamic>.from(calendarData['meetings'] ?? [])
          .whereType<Map>()
          .map((meeting) => Map<String, dynamic>.from(meeting))
          .toList();
      final attendance = List<dynamic>.from(attendanceData['meetings'] ?? []);
      for (final controller in _hoursControllers.values) {
        controller.dispose();
      }
      _hoursControllers.clear();
      for (final meeting in calendar) {
        final date = meeting['date']?.toString() ?? '';
        final defaultHours = _isPastOrToday(date)
            ? _actualHoursForDateFrom(attendance, date)
            : 0.0;
        _hoursControllers[meeting['id'].toString()] = TextEditingController(
          text: defaultHours == 0 ? '' : defaultHours.toString(),
        );
      }
      if (!mounted) return;
      setState(() {
        _calendar = calendar;
        _attendance = attendance;
        _currentTotalHours =
            (attendanceData['totalMeetingHours'] as num?)?.toDouble() ?? 0;
        _fullSemesterRequiredHours =
            (attendanceData['fullSemesterRequiredHours'] as num?)?.toDouble() ??
            235;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Unable to load the attendance calculator.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _actualHoursForDateFrom(List<dynamic> attendance, String date) {
    for (final item in attendance) {
      if (item['date']?.toString().split(' ').first == date) {
        if (item['error'] == true || item['error']?.toString() == 'true')
          return 0;
        return (item['durationHours'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  double get _projectedHours {
    var projected = _attendance.fold<double>(0, (sum, item) {
      if (item['error'] == true || item['error']?.toString() == 'true')
        return sum;
      return sum + ((item['durationHours'] as num?)?.toDouble() ?? 0);
    });
    for (final meeting in _calendar) {
      final date = meeting['date']?.toString() ?? '';
      final entered =
          double.tryParse(
            _hoursControllers[meeting['id'].toString()]?.text.trim() ?? '',
          ) ??
          0;
      if (_isPastOrToday(date)) projected -= _actualHoursForDate(date);
      projected += entered;
    }
    return projected < 0 ? 0 : projected;
  }

  double get _projectedRequiredHours =>
      _currentTotalHours +
      _calendar
          .where(
            (meeting) => !_isPastOrToday(meeting['date']?.toString() ?? ''),
          )
          .fold<double>(
            0,
            (sum, meeting) =>
                sum + ((meeting['totalHours'] as num?)?.toDouble() ?? 0),
          );

  @override
  void dispose() {
    for (final controller in _hoursControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final required = _projectedRequiredHours;
    final percentage = required == 0 ? 0 : (_projectedHours / required * 100);
    final fullSemesterPercentage = _fullSemesterRequiredHours == 0
        ? 0
        : (_projectedHours / _fullSemesterRequiredHours * 100);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryRed,
        title: const Text(
          'Attendance Calculator',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadCalculator,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryRed))
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(fontFamily: 'Poppins'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _primaryRed.withOpacity(.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _primaryRed,
                          ),
                        ),
                        const Text(
                          'Projected attendance',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: _accentRed,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_projectedHours.toStringAsFixed(2)} of ${required.toStringAsFixed(2)} hours',
                          style: const TextStyle(fontFamily: 'Poppins'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Full semester: ${fullSemesterPercentage.toStringAsFixed(1)}% of ${_fullSemesterRequiredHours.toStringAsFixed(2)} required hours',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Enter the hours you expect to attend. Blank means absent. Past meetings begin with your official attendance; flagged meetings begin at 0 and may be adjusted here for planning only.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _calendar.isEmpty
                        ? const Center(
                            child: Text(
                              'No published meetings yet.',
                              style: TextStyle(fontFamily: 'Poppins'),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _calendar.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final meeting = _calendar[index];
                              final id = meeting['id'].toString();
                              final past = _isPastOrToday(
                                meeting['date']?.toString() ?? '',
                              );
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${meeting['title']} · ${meeting['date']}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${meeting['startTime']}–${meeting['endTime']} · ${(meeting['totalHours'] as num?)?.toStringAsFixed(2) ?? '0.00'} meeting hours${past ? ' · completed' : ''}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: SizedBox(
                                  width: 84,
                                  child: TextField(
                                    controller: _hoursControllers[id],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'My hrs',
                                      isDense: true,
                                    ),
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                    ),
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

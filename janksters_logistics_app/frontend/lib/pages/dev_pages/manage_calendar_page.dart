import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ManageCalendarPage extends StatefulWidget {
  const ManageCalendarPage({super.key});

  @override
  State<ManageCalendarPage> createState() => _ManageCalendarPageState();
}

class _ManageCalendarPageState extends State<ManageCalendarPage> {
  static const _baseUrl = 'https://logistics-app-backend-o9t7.onrender.com';
  static const _primaryRed = Color(0xFFE30F13);
  final _title = TextEditingController();
  final _date = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _hours = TextEditingController();
  final _notes = TextEditingController();
  List<Map<String, dynamic>> _meetings = [];
  bool _published = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/attendance/calendar/manage'),
      );
      if (response.statusCode != 200) throw Exception();
      final data = jsonDecode(response.body);
      if (mounted)
        setState(
          () => _meetings = List<dynamic>.from(data['meetings'] ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
        );
    } catch (_) {
      if (mounted) _message('Unable to load calendar.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _meetingBody({bool? published}) => {
    'title': _title.text.trim(),
    'date': _date.text.trim(),
    'startTime': _start.text.trim(),
    'endTime': _end.text.trim(),
    'totalHours': double.tryParse(_hours.text.trim()) ?? -1,
    'notes': _notes.text.trim(),
    'published': published ?? _published,
  };

  Future<void> _addMeeting() async {
    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/attendance/calendar'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_meetingBody()),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 201) {
        for (final controller in [
          _title,
          _date,
          _start,
          _end,
          _hours,
          _notes,
        ]) {
          controller.clear();
        }
        _published = true;
        await _loadMeetings();
      } else {
        _message(data['error'] ?? 'Unable to add meeting.');
      }
    } catch (_) {
      if (mounted) _message('Unable to add meeting.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePublished(
    Map<String, dynamic> meeting,
    bool published,
  ) async {
    setState(() => _saving = true);
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/attendance/calendar/${meeting['id']}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({...meeting, 'published': published}),
      );
      if (response.statusCode == 200)
        await _loadMeetings();
      else if (mounted)
        _message('Unable to update meeting.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteMeeting(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete meeting?',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        content: const Text(
          'This removes it from the published calendar and calculator.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/attendance/calendar/$id'),
      );
      if (response.statusCode == 200)
        await _loadMeetings();
      else if (mounted)
        _message('Unable to delete meeting.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: const TextStyle(fontFamily: 'Poppins')),
    ),
  );

  @override
  void dispose() {
    for (final controller in [_title, _date, _start, _end, _hours, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: _primaryRed,
      title: const Text(
        'Meeting Calendar',
        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: _primaryRed))
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Add and publish meetings for the student attendance calculator.',
                  style: TextStyle(fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Meeting name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _date,
                        decoration: const InputDecoration(
                          labelText: 'Date (M/D/YYYY)',
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _start,
                        decoration: const InputDecoration(
                          labelText: 'Start time',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _end,
                        decoration: const InputDecoration(
                          labelText: 'End time',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _hours,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Total hours',
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Publish for students',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  value: _published,
                  activeColor: _primaryRed,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _published = value),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _addMeeting,
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Add Meeting',
                      style: TextStyle(fontFamily: 'Poppins'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryRed,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _meetings.isEmpty
                      ? const Center(
                          child: Text(
                            'No meetings planned.',
                            style: TextStyle(fontFamily: 'Poppins'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _meetings.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final meeting = _meetings[index];
                            return ListTile(
                              title: Text(
                                '${meeting['title']} · ${meeting['date']}',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${meeting['startTime']}–${meeting['endTime']} · ${meeting['totalHours']} hours${(meeting['notes']?.toString().isNotEmpty ?? false) ? '\n${meeting['notes']}' : ''}',
                                style: const TextStyle(fontFamily: 'Poppins'),
                              ),
                              isThreeLine:
                                  meeting['notes']?.toString().isNotEmpty ??
                                  false,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch.adaptive(
                                    value: meeting['published'] == true,
                                    activeColor: _primaryRed,
                                    onChanged: _saving
                                        ? null
                                        : (value) =>
                                              _changePublished(meeting, value),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: _primaryRed,
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => _deleteMeeting(
                                            meeting['id'].toString(),
                                          ),
                                  ),
                                ],
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

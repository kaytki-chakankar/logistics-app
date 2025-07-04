import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AttendancePage extends StatefulWidget {
  final String email;

  const AttendancePage({required this.email, super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  int? attendanceMinutes;
  int? attendanceCount;
  bool isFlagged = false;
  bool isLoading = false;
  String? userEmail;

  @override
  void initState() {
    super.initState();
    userEmail = FirebaseAuth.instance.currentUser?.email;
    fetchAttendance();
  }

  Future<void> fetchAttendance() async {
    if (userEmail == null) return;

    setState(() => isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('http://localhost:3000/attendance/$userEmail'),
      );

      final data = json.decode(response.body);
      print('Decoded data: $data');

      if (!mounted) return;

      setState(() {
        isFlagged = data['flagged'] ?? false;
        attendanceCount = data['attendanceCount'];

        if (!isFlagged && data['totalMinutesAttended'] != null) {
          attendanceMinutes = data['totalMinutesAttended'];
        }
      });
    } catch (e) {
      print('Failed to fetch attendance: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = isFlagged
        ? 'You either have < 2 check-ins or comments.\nAttendance count: $attendanceCount'
        : attendanceMinutes != null
            ? 'You attended for $attendanceMinutes minutes.'
            : 'Could not fetch attendance.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Checker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : Text(displayText, textAlign: TextAlign.center),
      ),
    );
  }
}

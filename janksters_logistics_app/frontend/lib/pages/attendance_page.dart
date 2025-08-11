import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_page.dart';
import 'links_page.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  double? totalHours;
  double? attendancePercentage;
  List<dynamic> meetings = [];
  bool isLoading = false;
  String? userEmail;
  String errorMessage = '';

  final List<String> developerEmails = [
    'kchakankar27@ndsj.org',
  ];

  @override
  void initState() {
    super.initState();
    userEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    //userEmail = "aarjun27@ndsj.org"; 
    _loadCachedAttendance(); // load cached data first for instant display
    fetchAttendance(); // then fetch fresh data
  }

  Future<void> _loadCachedAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('attendanceData');
    if (cached != null && mounted) {
      try {
        final cachedData = json.decode(cached);
        setState(() {
          totalHours = (cachedData['totalHours'] as num?)?.toDouble() ?? 0.0;
          attendancePercentage = (cachedData['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
          meetings = cachedData['meetings'] ?? [];
          errorMessage = 'Showing cached data';
        });
      } catch (e) {
        // ignore cache parse errors silently
      }
    }
  }

  Future<void> fetchAttendance() async {
    if (userEmail == null) {
      setState(() {
        errorMessage = 'No user email found.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    final url = Uri.parse('http://localhost:3000/attendance/$userEmail');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (!mounted) return;

        setState(() {
          totalHours = (data['totalHours'] as num?)?.toDouble() ?? 0.0;
          attendancePercentage = (data['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
          meetings = data['meetings'] ?? [];
          errorMessage = '';
        });

        // Save fetched data to cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('attendanceData', response.body);
      } else {
        setState(() {
          errorMessage = 'Failed to load attendance. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      // On error, load cached data if available
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('attendanceData');
      if (cached != null && mounted) {
        try {
          final cachedData = json.decode(cached);
          setState(() {
            totalHours = (cachedData['totalHours'] as num?)?.toDouble() ?? 0.0;
            attendancePercentage = (cachedData['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
            meetings = cachedData['meetings'] ?? [];
            errorMessage = 'Showing cached data (offline or error)';
          });
        } catch (e) {
          setState(() {
            errorMessage = 'Error fetching attendance: $e';
          });
        }
      } else {
        setState(() {
          errorMessage = 'Error fetching attendance: $e';
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool get isDeveloper => developerEmails.contains(userEmail);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              child: Text('Navigation', style: TextStyle(fontSize: 20)),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Attendance'),
              onTap: () => Navigator.pop(context),
            ),
            if (isDeveloper)
              ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('Developer Tools'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DeveloperPage()),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Important Links'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LinksPage()),
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('Attendance Checker'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchAttendance,
            tooltip: 'Refresh Attendance',
          ),
        ],
      ),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : errorMessage.isNotEmpty
                ? Text(errorMessage, style: const TextStyle(color: Colors.red))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Attendance percentage: ${attendancePercentage?.toStringAsFixed(2) ?? '0.00'}%',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        if (meetings.isEmpty)
                          const Text('No attendance records found.')
                        else
                          Expanded(
                            child: ListView.builder(
                              itemCount: meetings.length,
                              itemBuilder: (context, index) {
                                final meeting = meetings[index];
                                final date = meeting['date'] ?? 'Unknown date';
                                final duration = (meeting['durationHours'] ?? 0.0) as double;

                                if (meeting['error'] == true) {
                                  final reason = meeting['reason'] ?? 'Flagged entry';
                                  return ListTile(
                                    leading: const Icon(Icons.warning, color: Colors.red),
                                    title: Text('$date - flagged'),
                                    subtitle: Text(reason, style: const TextStyle(color: Colors.red)),
                                  );
                                } else if (duration == 0) {
                                  return ListTile(
                                    leading: const Icon(Icons.close, color: Colors.grey),
                                    title: Text('$date - absent'),
                                    subtitle: const Text('Did not attend'),
                                  );
                                } else {
                                  return ListTile(
                                    leading: const Icon(Icons.check_circle, color: Colors.green),
                                    title: Text(date),
                                    trailing: Text('${duration.toStringAsFixed(2)} hours'),
                                  );
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

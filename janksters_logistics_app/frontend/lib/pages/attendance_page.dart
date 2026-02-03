import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_pages/dev_page.dart';
import 'links_page.dart';
import 'preseason_stats.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  double? totalHours = 0;
  double? attendancePercentage;
  List<dynamic> meetings = [];
  bool isLoading = false;
  String? userEmail;
  String errorMessage = '';

  final List<String> developerEmails = [
    'kchakankar27@ndsj.org',
    'aferrer@ndsj.org',
    'bfarrer@ndsj.org',
    'abhardwaj26@ndsj.org',
    'thensley26@ndsj.org',
    'aarjun27@ndsj.org',
    'mcarrillo@ndsj.org'
  ];

  // team theme colors
  final Color primaryRed = const Color(0xFFE30F13);
  final Color accentRed = const Color(0xFF6C1016);
  final Color backgroundWhite = Colors.white;
  final Color blackText = Colors.black87;

  @override
  void initState() {
    super.initState();
    userEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    _loadCachedAttendance();
    fetchAttendance();
  }

  Future<void> _loadCachedAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('attendanceData');
    if (cached != null && mounted) {
      try {
        final cachedData = json.decode(cached);
        setState(() {
          totalHours = (cachedData['totalHoursAttended'] as num?)?.toDouble() ?? 0.0;
          attendancePercentage = (cachedData['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
          meetings = (cachedData['meetings'] as List<dynamic>?)
                  ?.where((m) =>
                      m['date'] != null &&
                      (m.containsKey('durationHours') ||
                          m['error'] == true ||
                          m['error']?.toString() == 'true'))
                  .toList() ??
              [];

          meetings.sort((a, b) {
            final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime(1970);
            final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime(1970);
            return dateA.compareTo(dateB);
          });

          errorMessage = 'Showing cached data';
        });
        print('Loaded cached meetings: $meetings');
      } catch (e) {
        print('Failed to parse cached attendance: $e');
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

    final url = Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/$userEmail');

    // testing purposes only
    // final url = Uri.parse('http://localhost:3000/attendance/$userEmail');


    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (!mounted) return;

        setState(() {
          totalHours = (data['totalHoursAttended'] as num?)?.toDouble() ?? 0.0;
          attendancePercentage = (data['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
          meetings = (data['meetings'] as List<dynamic>?)
                  ?.where((m) =>
                      m['date'] != null &&
                      (m.containsKey('durationHours') ||
                          m['error'] == true ||
                          m['error']?.toString() == 'true'))
                  .toList() ??
              [];

          meetings.sort((a, b) {
            final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime(1970);
            final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime(1970);
            return dateA.compareTo(dateB);;
          });

          errorMessage = '';
        });

        print('Fetched meetings: $meetings');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('attendanceData', response.body);
      } else {
        setState(() {
          errorMessage = 'Failed to load attendance. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('attendanceData');
      if (cached != null && mounted) {
        try {
          final cachedData = json.decode(cached);
          setState(() {
            totalHours = (cachedData['totalHoursAttended'] as num?)?.toDouble() ?? 0.0;
            attendancePercentage = (cachedData['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
            meetings = (cachedData['meetings'] as List<dynamic>?)
                    ?.where((m) =>
                        m['date'] != null &&
                        (m.containsKey('durationHours') ||
                            m['error'] == true ||
                            m['error']?.toString() == 'true'))
                    .toList() ??
                [];

            meetings.sort((a, b) {
              final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime(1970);
              final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime(1970);
              return dateA.compareTo(dateB);;
            });

            errorMessage = 'Showing cached data (offline or error)';
          });
          print('Loaded cached meetings after fetch error: $meetings');
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

  double calculateFullSemesterAttendance() {
    if (meetings.isEmpty) return 0.0;

    const totalHoursExpected = 140;

    final attendedHours = meetings.fold<double>(0.0, (sum, m) {
      if (m['error'] == true || m['error']?.toString() == 'true') return sum;
      return sum + ((m['durationHours'] ?? 0.0) as double);
    });

    return (attendedHours / totalHoursExpected * 100).clamp(0.0, 100.0);
  }

  bool get isDeveloper => developerEmails.contains(userEmail);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundWhite,
      drawer: Drawer(
        child: Container(
          color: backgroundWhite,
          child: ListView(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: primaryRed,
                ),
                child: const Center(
                  child: Text(
                    'Navigation',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.home, color: primaryRed),
                title: Text('Attendance',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: blackText,
                        fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context),
              ),
              if (isDeveloper)
                ListTile(
                  leading: Icon(Icons.developer_mode, color: primaryRed),
                  title: Text('Developer Tools',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: blackText,
                          fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DeveloperPage()),
                    );
                  },
                ),
              ListTile(
                leading: Icon(Icons.link, color: primaryRed),
                title: Text('Important Links',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: blackText,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LinksPage()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.calendar_month, color: primaryRed),
                title: Text('Preseason Attendance',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: blackText,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PreseasonStats()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.logout, color: primaryRed),
                title: Text('Logout',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: blackText,
                        fontWeight: FontWeight.w600)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: primaryRed,
        title: const Text(
          'Attendance Checker',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
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
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      errorMessage,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Column(
                      children: [
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            StylishCircularIndicator(
                              percentage: attendancePercentage ?? 0,
                              primaryRed: primaryRed,
                              accentRed: accentRed,
                              size: 250,
                              label: 'Attendance',
                            ),
                            const SizedBox(width: 75),
                            StylishCircularIndicator(
                              percentage: calculateFullSemesterAttendance(),
                              primaryRed: primaryRed,
                              accentRed: accentRed,
                              size: 200,
                              label: 'Full\nSemester',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: meetings.isEmpty
                              ? Center(
                                  child: Text(
                                    'No attendance records found.',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 18,
                                      color: blackText,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: meetings.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final meeting = meetings[index];
                                    final date = meeting['date'] ?? 'Unknown date';
                                    final duration = (meeting['durationHours'] ?? 0.0) as double;

                                    if (meeting['error'] == true ||
                                        meeting['error']?.toString() == 'true') {
                                      final reason = meeting['reason'] ?? 'Flagged entry';
                                      return ListTile(
                                        leading: Icon(Icons.warning, color: primaryRed),
                                        title: Text(
                                          '$date - flagged',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w600,
                                            color: primaryRed,
                                          ),
                                        ),
                                        subtitle: Text(
                                          reason,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: primaryRed.withOpacity(0.9),
                                          ),
                                        ),
                                      );
                                    } else if (duration == 0) {
                                      return ListTile(
                                        leading: Icon(Icons.close, color: Colors.grey.shade600),
                                        title: Text(
                                          '$date - absent',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Did not attend',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      );
                                    } else {
                                      return ListTile(
                                        leading: Icon(Icons.check_circle, color: accentRed),
                                        title: Text(
                                          date,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w600,
                                            color: blackText,
                                          ),
                                        ),
                                        trailing: Text(
                                          '${duration.toStringAsFixed(2)} hours',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: accentRed,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
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

class StylishCircularIndicator extends StatelessWidget {
  final double percentage;
  final Color primaryRed;
  final Color accentRed;
  final double size;
  final String? label;

  const StylishCircularIndicator({
    required this.percentage,
    required this.primaryRed,
    required this.accentRed,
    this.size = 160,
    this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final double clampedPercent = (percentage / 100).clamp(0.0, 1.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: primaryRed.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GradientCirclePainter(clampedPercent, primaryRed, accentRed),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: size / 4.5,
                  fontWeight: FontWeight.bold,
                  color: primaryRed,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label ?? 'Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: size / 10,
                  color: accentRed,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradientCirclePainter extends CustomPainter {
  final double progress;
  final Color primaryRed;
  final Color accentRed;

  _GradientCirclePainter(this.progress, this.primaryRed, this.accentRed);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 20.0;
    final rect = Offset.zero & size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;

    final bgPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, bgPaint);

    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + 2 * math.pi * progress,
      colors: [
        primaryRed,
        accentRed,
      ],
      stops: const [0.0, 1.0],
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientCirclePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryRed != primaryRed ||
        oldDelegate.accentRed != accentRed;
  }
}

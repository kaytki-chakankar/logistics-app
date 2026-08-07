import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ViewFullTeamAttendancePage extends StatefulWidget {
  const ViewFullTeamAttendancePage({super.key});

  @override
  State<ViewFullTeamAttendancePage> createState() => _ViewFullTeamAttendancePageState();
}

class _ViewFullTeamAttendancePageState extends State<ViewFullTeamAttendancePage> {
  late Future<Map<String, dynamic>> _attendanceFuture;
  bool isPreseason = false;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _attendanceFuture = fetchFullTeamAttendance();
  }

  Future<Map<String, dynamic>> fetchFullTeamAttendance() async {
    final url = Uri.parse(
      "https://logistics-app-backend-o9t7.onrender.com/attendance/team/full?isPreseason=${isPreseason.toString()}"
    );

    // testing purposes only
    // final url = Uri.parse(
    //   "http://localhost:3000/attendance/team/full?isPreseason=${isPreseason.toString()}"
    // );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch full team attendance");
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Color rowBackground(int percent) {
    if (percent >= 75) {
      return Colors.green.withOpacity(0.12);
    } else {
      return Colors.red.withOpacity(0.12);
    }
  }

  String shortDate(String date) {
    final parts = date.split('/');
    return parts.length >= 2 ? '${parts[0]}/${parts[1]}' : date;
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Full Team Attendance"),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _attendanceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error loading attendance: ${snapshot.error}"),
            );
          }

          final data = snapshot.data!;
          final dates = List<String>.from(data["dates"]);
          final team = List<Map<String, dynamic>>.from(data["team"]);

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Attendance Overview",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        const Text("Build"),
                        Switch(
                          value: isPreseason,
                          onChanged: (v) async {
                            setState(() => isPreseason = v);
                            setState(() => _attendanceFuture = fetchFullTeamAttendance());
                          },
                        ),
                        const Text("Preseason")
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: const [
                    _AttendanceLegend(icon: '✓', label: 'Attended', color: Colors.green),
                    _AttendanceLegend(icon: '✗', label: 'Absent', color: Colors.red),
                    _AttendanceLegend(icon: '⚠', label: 'Flagged', color: Colors.orange),
                    _AttendanceLegend(icon: '—', label: 'No record', color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tableWidth = math.max(
                        constraints.maxWidth,
                        280 + (dates.length * 66.0),
                      );
                      return Scrollbar(
                        controller: _horizontalController,
                        thumbVisibility: true,
                        notificationPredicate: (notification) => notification.depth == 0,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: Scrollbar(
                              controller: _verticalController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _verticalController,
                                child: DataTable(
                                  columnSpacing: 16,
                                  headingRowHeight: 52,
                                  dataRowMinHeight: 46,
                                  dataRowMaxHeight: 46,
                                  columns: [
                                    const DataColumn(label: SizedBox(width: 190, child: Text('Member', style: TextStyle(fontWeight: FontWeight.bold)))),
                                    const DataColumn(label: Text('%', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ...dates.map((date) => DataColumn(
                                      label: Tooltip(
                                        message: date,
                                        child: SizedBox(width: 42, child: Center(child: Text(shortDate(date), style: const TextStyle(fontWeight: FontWeight.bold)))),
                                      ),
                                    )),
                                  ],
                                  rows: team.map((member) {
                                    final email = member['email'];
                                    final percent = member['attendancePercent'] as int;
                                    final row = List<Map<String, dynamic>>.from(member['row']);
                                    return DataRow(
                                      color: WidgetStateProperty.all(rowBackground(percent)),
                                      cells: [
                                        DataCell(SizedBox(width: 190, child: Text(email, overflow: TextOverflow.ellipsis))),
                                        DataCell(Text('$percent%')),
                                        ...row.map((cell) {
                                          final status = cell['status'];
                                          final symbol = status == 'attended' ? '✓' : status == 'missed' ? '✗' : status == 'flagged' ? '⚠' : '—';
                                          final color = status == 'attended' ? Colors.green : status == 'missed' ? Colors.red : status == 'flagged' ? Colors.orange : Colors.grey;
                                          final label = status == 'flagged' ? cell['reason'] ?? 'Flagged entry' : status == 'attended' ? '${cell['hours']} hours attended' : status == 'missed' ? 'Absent' : 'No record';
                                          return DataCell(Tooltip(message: label.toString(), child: Center(child: Text(symbol, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color))));
                                        }),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AttendanceLegend extends StatelessWidget {
  const _AttendanceLegend({required this.icon, required this.label, required this.color});

  final String icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

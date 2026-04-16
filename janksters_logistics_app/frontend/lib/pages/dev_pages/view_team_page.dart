import 'dart:convert';
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

                Expanded(
                  child: Scrollbar(
                    controller: _verticalController,
                    child: SingleChildScrollView(
                      controller: _verticalController,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // FIXED EMAIL COLUMN
                          Column(
                            children: [
                              Container(
                                height: 48,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: const Text(
                                  "Email",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...team.map((member) {
                                final percent = member["attendancePercent"] as int;

                                return Container(
                                  height: 44,
                                  width: 180,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  alignment: Alignment.centerLeft,
                                  color: rowBackground(percent),
                                  child: Text(member["email"]),
                                );
                              }),
                            ],
                          ),

                          // SCROLLABLE DATE GRID
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: SingleChildScrollView(
                                child: DataTable(
                                  columnSpacing: 24,
                                  headingRowHeight: 48,
                                  dataRowHeight: 44,
                                  columns: [
                                    const DataColumn(label: Text("Email")),
                                    const DataColumn(label: Text("%")),
                                    ...dates.map((d) => DataColumn(label: Text(d))),
                                  ],
                                  rows: team.map((member) {
                                    final email = member["email"];
                                    final percent = member["attendancePercent"] as int;
                                    final row =
                                        List<Map<String, dynamic>>.from(member["row"]);

                                    return DataRow(
                                      color: MaterialStateProperty.all(
                                        rowBackground(percent),
                                      ),
                                      cells: [
                                        DataCell(Text(email)),
                                        DataCell(Text("$percent%")),
                                        ...row.map((cell) {
                                          final status = cell["status"];
                                          String symbol = "";
                                          Color color = Colors.black;

                                          switch (status) {
                                            case "attended":
                                              symbol = "✓";
                                              color = Colors.green;
                                              break;
                                            case "missed":
                                              symbol = "✗";
                                              color = Colors.red;
                                              break;
                                            case "flagged":
                                              symbol = "⚠";
                                              color = Colors.orange;
                                              break;
                                            default:
                                              symbol = "";
                                          }

                                          return DataCell(
                                            Center(
                                              child: Text(
                                                symbol,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
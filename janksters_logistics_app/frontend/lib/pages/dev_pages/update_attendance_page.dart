import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class UpdateAttendancePage extends StatefulWidget {
  const UpdateAttendancePage({super.key});

  @override
  State<UpdateAttendancePage> createState() => _UpdateAttendancePageState();
}

class _UpdateAttendancePageState extends State<UpdateAttendancePage> {
  List<dynamic> flaggedEmails = [];
  List<dynamic> allSheetRows = [];

  final TextEditingController _sheetController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController commentController = TextEditingController();
  final TextEditingController hoursController = TextEditingController();

  bool isLoading = false;
  String statusMessage = '';
  int currentIndex = 0;
  bool keepFlagged = true;

  static const sheetTimestampKey = "Timestamp";
  static const sheetEmailKey = "Email Address";
  static const sheetCommentKey = "Additional Comments?";

  String formatTimestamp(String? value) {
    if (value == null || value.isEmpty) return "Unknown";

    try {
      final dt = DateTime.tryParse(value);
      if (dt == null) return value;

      return "${dt.month}/${dt.day}/${dt.year} "
          "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return value;
    }
  }

  Future<void> fetchFlaggedForDate(String date) async {
    setState(() => isLoading = true);

    try {
      final encoded = Uri.encodeComponent(date);

      final url = Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/flagged?sheet=$encoded');

      // testing purposes only
      // final url = Uri.parse('http://localhost:3000/attendance/flagged?sheet=$encoded');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> results = decoded["results"] ?? [];
        flaggedEmails = results.where((e) => (e["flagged"] ?? false) == true).map((e) {
          return {
            ...e,
            "date": e["date"] ?? date,
            "reason": e["reason"] ?? "(no reason provided)"
          };
        }).toList();
        currentIndex = 0;

        if (flaggedEmails.isNotEmpty) {
          loadCurrentEntry();
        }
      } else {
        flaggedEmails = [];
      }
    } catch (_) {
      flaggedEmails = [];
    } finally {
      setState(() => isLoading = false);
    }
  }

void loadCurrentEntry() {
  if (currentIndex >= flaggedEmails.length) return;

  final entry = flaggedEmails[currentIndex];

  hoursController.text = entry["durationHours"]?.toString() ?? "";
  commentController.text = entry["reason"] ?? "";
  keepFlagged = entry["error"] ?? true;

  setState(() {});

  final sheet = _sheetController.text.trim();
  final email = entry["email"];
  if (sheet.isNotEmpty && email != null && email.isNotEmpty) {
    fetchAllRows(sheet, email);
  } else {
    allSheetRows = [];
  }
}



  Future<void> updateMasterAttendance(String sheetName, double meetingHours) async {
    setState(() {
      isLoading = true;
      statusMessage = '';
    });

    try {
      final url = Uri.http(
        'logistics-app-backend-o9t7.onrender.com',
        '/attendance/update',
        {
          'sheet': sheetName,
          'hours': meetingHours.toString(),
        },
      );

      // testing purposes only
      // final url = Uri.http(
      //   'localhost:3000',
      //   '/attendance/update',
      //   {
      //     'sheet': sheetName,
      //     'hours': meetingHours.toString(),
      //   },
      // );

      print("UPDATE REQUEST URL: $url");

      final r = await http.get(url);

      if (r.statusCode != 200) {
        statusMessage = "Server error: ${r.statusCode}";
        return;
      }

      if (!(r.headers['content-type'] ?? "").startsWith("application/json")) {
        statusMessage = "Backend did not return JSON.";
        return;
      }

      final decoded = json.decode(r.body);

      statusMessage = decoded['message'] ?? 'Update successful.';

      await fetchFlaggedForDate(sheetName);

      if (flaggedEmails.isNotEmpty) {
        await fetchAllRows(sheetName, flaggedEmails[currentIndex]["email"]);
      }

    } catch (e) {
      statusMessage = "Error updating: $e";
      flaggedEmails = [];
    } finally {
      setState(() => isLoading = false);
    }
  }


  Future<void> fetchAllRows(String sheetName, String email) async {
    setState(() => isLoading = true);

    try {
      final encodedSheet = Uri.encodeComponent(sheetName);
      final encodedEmail = Uri.encodeComponent(email);
      final url = Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/raw/$encodedEmail?sheet=$encodedSheet');

      // testing purposes only
      // final url = Uri.parse('http://localhost:3000/attendance/raw/$encodedEmail?sheet=$encodedSheet');

      final r = await http.get(url);

      if (r.statusCode == 200) {
        final decoded = json.decode(r.body);
        allSheetRows = decoded["results"] ?? [];
        print("allSheetRows (${allSheetRows.length} rows):");
        for (var row in allSheetRows) {
          print("timestamp: ${row[sheetTimestampKey]}, "
                "email: ${row[sheetEmailKey]}, "
                "comments: ${row[sheetCommentKey]}");
        }
      } else {
        allSheetRows = [];
      }
    } catch (_) {
      allSheetRows = [];
    } finally {
      setState(() => isLoading = false);
    }
  }


  Future<void> resolveEntry() async {
    if (currentIndex >= flaggedEmails.length) return;
    final entry = flaggedEmails[currentIndex];

    final url = Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/resolve');

    // testing purposes only
    // final url = Uri.parse("http://localhost:3000/attendance/resolve");
    
    final body = {
      "email": entry["email"],
      "date": entry["date"],
      "keepFlagged": keepFlagged,
    };

    if (keepFlagged) {
      body["reason"] =
          commentController.text.isNotEmpty ? commentController.text : "(no reason provided)";
    } else {
      body["durationHours"] = double.tryParse(hoursController.text) ?? 0;
    }

    setState(() => isLoading = true);

    try {
      final r = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (r.statusCode == 200) {
        currentIndex++;

        if (currentIndex < flaggedEmails.length) {
          loadCurrentEntry(); 
        } else {
          statusMessage = "Review complete — all flagged entries processed.";
          allSheetRows = [];
        }
      } else {
        statusMessage = "Failed to update entry.";
      }
    } catch (e) {
      statusMessage = "Error updating entry: $e";
    } finally {
      setState(() => isLoading = false);
    }
  }



  @override
  void dispose() {
    _sheetController.dispose();
    _hoursController.dispose();
    hoursController.dispose();
    commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasEntry = flaggedEmails.isNotEmpty && currentIndex < flaggedEmails.length;

    return Scaffold(
      appBar: AppBar(title: const Text("Update Meeting Hours for the Team")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _sheetController,
                    decoration: const InputDecoration(
                      labelText: "Enter Sheet Name (e.g. 1/9/2025)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hoursController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Meeting Hours",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                final sheet = _sheetController.text.trim();
                final hours = double.tryParse(_hoursController.text.trim());
                if (sheet.isEmpty || hours == null) {
                  setState(() {
                    statusMessage = "Please provide sheet name and valid hours.";
                  });
                  return;
                }
                updateMasterAttendance(sheet, hours);
              },
              child: const Text("Update Master Attendance"),
            ),
            if (isLoading) const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
            if (statusMessage.isNotEmpty)
              Text(statusMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (hasEntry)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Flagged entry ${currentIndex + 1} of ${flaggedEmails.length}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text("Email: ${flaggedEmails[currentIndex]["email"]}"),
                      Text("Date: ${flaggedEmails[currentIndex]["date"] ?? _sheetController.text}"),
                      const SizedBox(height: 10),
                      TextField(
                        controller: hoursController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: "Edit hours",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commentController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: "Comment / reason",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Row(
                        children: [
                          Switch(
                            value: keepFlagged,
                            onChanged: (v) => setState(() => keepFlagged = v),
                          ),
                          const Text("Keep flagged"),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildRawSheetSectionForCurrentEmail(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: resolveEntry,
                            child: const Text("Save & Next"),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () {
                              currentIndex++;
                              if (currentIndex < flaggedEmails.length) {
                                loadCurrentEntry(); 
                              } else {
                                statusMessage = "Review complete — all flagged entries processed.";
                                allSheetRows = [];
                                setState(() {});
                              }
                            },
                            child: const Text("Skip"),
                          ),

                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawSheetSectionForCurrentEmail() {
    final currentEmail = flaggedEmails[currentIndex]["email"];

    final rows = allSheetRows
        .where((r) => ((r[sheetEmailKey] ?? "").toString().trim().toLowerCase() ==
                        currentEmail.toString().trim().toLowerCase()))
        .toList();
    
    if (rows.isEmpty) {
      return const Text(
        "No raw Google Sheet rows for this email.",
        style: TextStyle(fontStyle: FontStyle.italic),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Raw Google Sheet Entries",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            final commentValue = row[sheetCommentKey]?.toString() ?? "";
            final comment = commentValue.trim().isEmpty ? "(none)" : commentValue;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("timestamp: ${formatTimestamp(row[sheetTimestampKey])}"),
                  Text("email: ${row[sheetEmailKey] ?? "(missing)"}"),
                  Text("comments: $comment"),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

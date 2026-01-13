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
      return "${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return value;
    }
  }

  /* ---------------------- FETCH FLAGGED ---------------------- */

  Future<void> fetchFlaggedForDate(String date) async {
    setState(() => isLoading = true);
    try {
      final encoded = Uri.encodeComponent(date);
      final url = Uri.parse(
        'https://logistics-app-backend-o9t7.onrender.com/attendance/flagged?sheet=$encoded',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> results = decoded["results"] ?? [];

        flaggedEmails = results
            .where((e) => (e["flagged"] ?? false) == true)
            .map((e) {
          return {
            ...e,
            "date": e["date"] ?? date,
            "reason": e["reason"] ?? "(no reason provided)"
          };
        }).toList();

        currentIndex = 0; // only reset index here
      } else {
        flaggedEmails = [];
      }
    } catch (_) {
      flaggedEmails = [];
    } finally {
      setState(() => isLoading = false);
    }
  }

  /* ---------------------- LOAD ONE ENTRY ---------------------- */

  void loadCurrentEntry() {
    if (currentIndex >= flaggedEmails.length) return;

    final entry = flaggedEmails[currentIndex];

    hoursController.text = entry["durationHours"]?.toString() ?? "";
    commentController.text = entry["reason"] ?? "";
    keepFlagged = entry["error"] ?? true;

    final sheet = _sheetController.text.trim();
    final email = entry["email"];

    if (sheet.isNotEmpty && email != null && email.isNotEmpty) {
      fetchAllRows(sheet, email);
    } else {
      allSheetRows = [];
    }

    setState(() {});
  }

  /* ---------------------- UPDATE MASTER ---------------------- */

  Future<void> updateMasterAttendance(String sheetName, double meetingHours) async {
    setState(() {
      isLoading = true;
      statusMessage = '';
    });

    try {
      final url = Uri.https(
        'logistics-app-backend-o9t7.onrender.com',
        '/attendance/update',
        {
          'sheet': sheetName,
          'hours': meetingHours.toString(),
        },
      );

      final r = await http.get(url);

      if (r.statusCode != 200) {
        statusMessage = "Server error: ${r.statusCode}";
        return;
      }

      final decoded = json.decode(r.body);
      statusMessage = decoded['message'] ?? 'Update successful.';

      await fetchFlaggedForDate(sheetName);

      if (flaggedEmails.isNotEmpty) {
        loadCurrentEntry(); // only place this is called
      }

    } catch (e) {
      statusMessage = "Error updating: $e";
      flaggedEmails = [];
    } finally {
      setState(() => isLoading = false);
    }
  }

  /* ---------------------- RAW ROWS ---------------------- */

  Future<void> fetchAllRows(String sheetName, String email) async {
    setState(() => isLoading = true);

    try {
      final encodedSheet = Uri.encodeComponent(sheetName);
      final encodedEmail = Uri.encodeComponent(email);

      final url = Uri.parse(
        'https://logistics-app-backend-o9t7.onrender.com/attendance/raw/$encodedEmail?sheet=$encodedSheet',
      );

      final r = await http.get(url);

      if (r.statusCode == 200) {
        final decoded = json.decode(r.body);
        allSheetRows = decoded["results"] ?? [];
      } else {
        allSheetRows = [];
      }
    } catch (_) {
      allSheetRows = [];
    } finally {
      setState(() => isLoading = false);
    }
  }

  /* ---------------------- RESOLVE ---------------------- */

  Future<void> resolveEntry() async {
    if (currentIndex >= flaggedEmails.length) return;
    final entry = flaggedEmails[currentIndex];

    final url = Uri.parse(
      'https://logistics-app-backend-o9t7.onrender.com/attendance/resolve',
    );

    final body = {
      "email": entry["email"],
      "date": entry["date"],
      "keepFlagged": keepFlagged,
    };

    if (keepFlagged) {
      body["reason"] = commentController.text.isNotEmpty
          ? commentController.text
          : "(no reason provided)";
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
          statusMessage = "Review complete. All flagged entries processed.";
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

  /* ---------------------- UI ---------------------- */

  @override
  Widget build(BuildContext context) {
    final hasEntry = flaggedEmails.isNotEmpty && currentIndex < flaggedEmails.length;

    return Scaffold(
      appBar: AppBar(title: const Text("Update Meeting Hours")),
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
                      labelText: "Sheet name",
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
                      labelText: "Hours",
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
                  setState(() => statusMessage = "Enter sheet and hours.");
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
            if (hasEntry)
              Expanded(child: Center(child: Text("Reviewing ${currentIndex + 1} of ${flaggedEmails.length}")))
          ],
        ),
      ),
    );
  }
}

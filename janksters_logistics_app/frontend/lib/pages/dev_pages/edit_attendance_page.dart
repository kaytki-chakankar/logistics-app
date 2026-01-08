import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EditAttendancePage extends StatefulWidget {
  @override
  State<EditAttendancePage> createState() => _EditAttendancePageState();
}

class _EditAttendancePageState extends State<EditAttendancePage> {
  final emailController = TextEditingController();
  final dateController = TextEditingController();
  final durationController = TextEditingController();
  final reasonController = TextEditingController();

  bool isFlagged = false;
  Map<String, dynamic>? loadedEntry;

  Future<void> fetchEntry() async {
    final email = emailController.text.trim().toLowerCase();
    final date = dateController.text.trim();

    if (email.isEmpty || date.isEmpty) {
      showSnack("Email and date are required");
      return;
    }

    final res = await http.get(
      Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/$email')

      // testing purposes only
      // Uri.parse("http://localhost:3000/attendance/$email"),
    );

    if (res.statusCode != 200) {
      showSnack("Email not found");
      return;
    }

    final data = jsonDecode(res.body);
    final records = data["meetings"] ?? [];

    final match = records.firstWhere(
      (e) => e["date"] == date,
      orElse: () => {},
    );

    if (match.isEmpty) {
      showSnack("No meeting found for that date");
      return;
    }

    setState(() {
      loadedEntry = match;
      isFlagged = match.containsKey("error");

      if (isFlagged) {
        reasonController.text = match["reason"] ?? "";
        durationController.clear();
      } else {
        durationController.text =
            match["durationHours"]?.toString() ?? "";
        reasonController.clear();
      }
    });
  }

  Future<void> submitUpdate() async {
    final email = emailController.text.trim().toLowerCase();
    final date = dateController.text.trim();

    if (email.isEmpty || date.isEmpty) {
      showSnack("Email and date are required");
      return;
    }

    final payload = isFlagged
        ? {
            "date": date,
            "error": true,
            "reason": reasonController.text.trim(),
          }
        : {
            "date": date,
            "durationHours":
                double.tryParse(durationController.text.trim()) ?? 0,
          };

    final res = await http.post(
      Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/manual-update'),

      // testing purposes only
      // Uri.parse("http://localhost:3000/attendance/manual-update"),

      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "date": date,
        "payload": payload,
      }),
    );

    showSnack(
      res.statusCode == 200
          ? "Attendance updated successfully"
          : "Update failed",
    );
  }

  void showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Edit Attendance")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: "Email",
              ),
            ),

            SizedBox(height: 12),

            TextField(
              controller: dateController,
              decoration: InputDecoration(
                labelText: "Meeting Date (MM/DD/YYYY)",
              ),
            ),

            SizedBox(height: 16),

            ElevatedButton(
              onPressed: fetchEntry,
              child: Text("Load Entry"),
            ),

            if (loadedEntry != null) Divider(height: 32),

            if (loadedEntry != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Flagged Entry",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Switch(
                    value: isFlagged,
                    onChanged: (v) => setState(() => isFlagged = v),
                  ),
                ],
              ),

            if (!isFlagged && loadedEntry != null)
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Duration (hours)",
                ),
              ),

            if (isFlagged && loadedEntry != null)
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: "Flag Reason",
                ),
              ),

            SizedBox(height: 20),

            if (loadedEntry != null)
              ElevatedButton(
                onPressed: submitUpdate,
                child: Text("Save Changes"),
              ),
          ],
        ),
      ),
    );
  }
}

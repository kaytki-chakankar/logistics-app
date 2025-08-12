import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  List<String> flaggedEmails = [];
  final TextEditingController _sheetController = TextEditingController();
  bool isLoading = false;
  String statusMessage = '';

  Future<void> fetchFlaggedForDate(String date) async {
    setState(() {
      isLoading = true;
    });

    try {
      final encodedDate = Uri.encodeComponent(date);
      // Use "sheet" query param to match backend
      final url = Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/flagged?sheet=$encodedDate');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map && decoded.containsKey('results')) {
          final List<dynamic> results = decoded['results'];
          List<String> flagged = [];

          for (var entry in results) {
            final email = entry['email'] ?? '';
            final isFlagged = entry['flagged'] ?? false;

            if (isFlagged && email.isNotEmpty) {
              flagged.add(email);
            }
          }

          setState(() {
            flaggedEmails = flagged;
          });
        }
      } else {
        print('Failed to fetch flagged emails for date with status: ${response.statusCode}');
        setState(() {
          flaggedEmails = [];
        });
      }
    } catch (e) {
      print('Error fetching flagged emails for date: $e');
      setState(() {
        flaggedEmails = [];
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> updateMasterAttendance(String sheetName) async {
    setState(() {
      isLoading = true;
      statusMessage = '';
    });

    try {
      final encodedSheet = Uri.encodeComponent(sheetName);
      final url = Uri.parse('https://logistics-app-backend-o9t7.onrender.com/attendance/update?sheet=$encodedSheet');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        setState(() {
          statusMessage = decoded['message'] ?? 'Update successful.';
        });
        await fetchFlaggedForDate(sheetName);
      } else {
        try {
          final decoded = json.decode(response.body);
          setState(() {
            statusMessage = decoded['message'] ?? 'Update failed with status ${response.statusCode}';
          });
        } catch (_) {
          setState(() {
            statusMessage = 'Update failed with status ${response.statusCode}';
          });
        }
        flaggedEmails = [];
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Error updating: $e';
        flaggedEmails = [];
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Tools - Attendance Overview')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              controller: _sheetController,
              decoration: const InputDecoration(
                labelText: 'Enter Sheet Name (e.g. 1/9/2025)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                final sheet = _sheetController.text.trim();
                if (sheet.isNotEmpty) {
                  updateMasterAttendance(sheet);
                }
              },
              child: const Text('Update Master Attendance'),
            ),
            const SizedBox(height: 12),
            if (isLoading) const CircularProgressIndicator(),
            if (statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  statusMessage,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 12),
            if (flaggedEmails.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Flagged Emails:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: flaggedEmails.length,
                        itemBuilder: (context, index) {
                          final email = flaggedEmails[index];
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(email),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

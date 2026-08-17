import 'package:flutter/material.dart';
import 'package:janksters_logistics_app/pages/attendance_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'dev_pages/dev_page.dart';
import 'preseason_stats.dart';
import '../developer_access.dart';

class LinksPage extends StatefulWidget {
  const LinksPage({super.key});

  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  String? userEmail;
  List<Map<String, String>> links = [];
  bool isLoadingLinks = true;
  String? linksError;

  @override
  void initState() {
    super.initState();
    userEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    DeveloperAccess.load().then((emails) {
      if (mounted) setState(() => developerEmails = emails);
    });
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://logistics-app-backend-o9t7.onrender.com/important-links',
        ),
      );
      if (response.statusCode != 200) throw Exception('Unable to load links.');
      final data = jsonDecode(response.body);
      final loadedLinks = (data['links'] as List<dynamic>? ?? [])
          .map(
            (link) => {
              'title': link['title'].toString(),
              'url': link['url'].toString(),
            },
          )
          .toList();
      if (mounted) {
        setState(() {
          links = loadedLinks;
          isLoadingLinks = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          linksError = 'Unable to load links. Please try again later.';
          isLoadingLinks = false;
        });
      }
    }
  }

  final Color primaryRed = const Color(0xFFE30F13);
  final Color accentRed = const Color(0xFF6C1016);
  final Color backgroundWhite = Colors.white;
  final Color blackText = Colors.black87;

  List<String> developerEmails = [];

  bool get isDeveloper => developerEmails.contains(userEmail);

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

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
                decoration: BoxDecoration(color: primaryRed),
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
                title: Text(
                  'Attendance',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: blackText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AttendancePage()),
                  );
                },
              ),
              if (isDeveloper)
                ListTile(
                  leading: Icon(Icons.developer_mode, color: primaryRed),
                  title: Text(
                    'Developer Tools',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: blackText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                title: Text(
                  'Important Links',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: blackText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LinksPage()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.bar_chart, color: primaryRed),
                title: Text(
                  'Preseason Attendance',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: blackText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                title: Text(
                  'Logout',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: blackText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          'Important Links',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoadingLinks
          ? const Center(child: CircularProgressIndicator())
          : linksError != null
          ? Center(
              child: Text(
                linksError!,
                style: TextStyle(fontFamily: 'Poppins', color: accentRed),
              ),
            )
          : links.isEmpty
          ? const Center(
              child: Text(
                'No links have been added yet.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              itemCount: links.length,
              separatorBuilder: (_, __) =>
                  Divider(color: accentRed.withOpacity(0.3), thickness: 1),
              itemBuilder: (context, index) {
                final link = links[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: accentRed.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  elevation: 3,
                  shadowColor: accentRed.withOpacity(0.25),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 20,
                    ),
                    leading: Icon(Icons.link, color: primaryRed, size: 32),
                    title: Text(
                      link['title'] ?? 'Untitled',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    trailing: const Icon(Icons.open_in_new, color: Colors.grey),
                    onTap: () => _openLink(link['url'] ?? ''),
                    hoverColor: primaryRed.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

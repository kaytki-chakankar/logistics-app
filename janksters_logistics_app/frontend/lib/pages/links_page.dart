import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'dev_pages/dev_page.dart';
import 'preseason_stats.dart';



class LinksPage extends StatefulWidget {
  const LinksPage({super.key});

  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  String? userEmail;

  @override
  void initState() {
    super.initState();
    userEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  }

  static const List<Map<String, String>> links = [
    {
      'title': 'Leadership Drive',
      'url': 'https://drive.google.com/drive/folders/0ANydg9_JDsrrUk9PVA',
    },
    {
      'title': 'Team Calendar',
      'url': 'https://docs.google.com/spreadsheets/d/1VH-h4vqi3WZ0dV_-8Qf2T6R2lpBFExDJWNmpr447Zds/edit?gid=0#gid=0',
    },
    {
      'title': 'Team Resource Website',
      'url': 'https://sites.google.com/ndsj.org/jankster-resources/home',
    },
  ];

  final Color primaryRed = const Color(0xFFE30F13);
  final Color accentRed = const Color(0xFF6C1016);
  final Color backgroundWhite = Colors.white;
  final Color blackText = Colors.black87;

  final List<String> developerEmails = [
    'kchakankar27@ndsj.org',
    'aferrer@ndsj.org'
  ];

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
                leading: Icon(Icons.calendar_month, color: primaryRed),
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
          'Important Links',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: links.length,
        separatorBuilder: (_, __) => Divider(color: accentRed.withOpacity(0.3), thickness: 1),
        itemBuilder: (context, index) {
          final link = links[index];
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: accentRed.withOpacity(0.4), width: 1),
            ),
            elevation: 3,
            shadowColor: accentRed.withOpacity(0.25),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
      ),
    );
  }
}

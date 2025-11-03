import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LinksPage extends StatelessWidget {
  const LinksPage({super.key});

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

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  final Color primaryRed = const Color(0xFFE30F13);
  final Color accentRed = const Color(0xFF6C1016);
  final Color backgroundWhite = Colors.white;
  final Color blackText = Colors.black87;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundWhite,
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

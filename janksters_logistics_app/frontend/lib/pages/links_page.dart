import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LinksPage extends StatelessWidget {
  const LinksPage({super.key});

  // Make this static const so it can be used in a const widget
  static const List<Map<String, String>> links = [
    {
      'title': 'Team Google Drive',
      'url': 'https://drive.google.com/drive/folders/...',
    },
    {
      'title': 'Meeting Schedule',
      'url': 'https://docs.google.com/spreadsheets/d/...',
    },
    {
      'title': 'Club Website',
      'url': 'https://example.com',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Important Links')),
      body: ListView.builder(
        itemCount: links.length,
        itemBuilder: (context, index) {
          final link = links[index];
          return ListTile(
            leading: const Icon(Icons.link, color: Colors.blue),
            title: Text(link['title'] ?? 'Untitled'),
            onTap: () => _openLink(link['url'] ?? ''),
          );
        },
      ),
    );
  }
}

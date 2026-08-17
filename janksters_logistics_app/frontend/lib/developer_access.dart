import 'dart:convert';

import 'package:http/http.dart' as http;

class DeveloperAccess {
  static Future<List<String>> load() async {
    final response = await http.get(
      Uri.parse('https://logistics-app-backend-o9t7.onrender.com/developers'),
    );
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body);
    return (data['developers'] as List<dynamic>? ?? [])
        .map((email) => email.toString().toLowerCase())
        .toList();
  }
}

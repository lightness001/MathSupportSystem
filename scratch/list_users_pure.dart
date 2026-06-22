import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const url = 'https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/profiles';
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> profiles = jsonDecode(response.body);
      print('--- PROFILES ---');
      for (var p in profiles) {
        print('Username/Email: ${p['username'] ?? p['email']}, Role: ${p['role']}, Level: ${p['level']}, School: ${p['school']}');
      }
    } else {
      print('Failed to load profiles: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    print('Error: $e');
  }
}

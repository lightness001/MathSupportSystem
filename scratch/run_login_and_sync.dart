import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Login as 0700000002 and check links ===");

  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  final email = "0700000002_private_app@mathsupport.tz";
  final password = "password123";

  try {
    final loginRes = await http.post(
      Uri.parse("$urlBase/auth/v1/token?grant_type=password"),
      headers: {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (loginRes.statusCode == 200) {
      final data = jsonDecode(loginRes.body);
      final token = data['access_token'];
      final userId = data['user']['id'];
      print("Login SUCCESS! User ID: $userId");

      // Query parent_child_links
      print("Querying links...");
      final res = await http.get(
        Uri.parse("$urlBase/rest/v1/parent_child_links?select=*"),
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        final List links = jsonDecode(res.body);
        print("Found ${links.length} links:");
        for (var l in links) {
          print("  - Student: ${l['student_username']} | School: ${l['school']} | Grade: ${l['student_level']}");
        }
      } else {
        print("Failed to query links: ${res.statusCode} - ${res.body}");
      }
    } else {
      print("Login failed: ${loginRes.statusCode} - ${loginRes.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

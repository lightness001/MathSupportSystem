import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Login as 0700000002 and try to insert link ===");

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

      // Try to insert a child link: lightness2026
      print("Attempting to insert link for lightness2026...");
      final insertRes = await http.post(
        Uri.parse("$urlBase/rest/v1/parent_child_links"),
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        body: jsonEncode({
          'parent_id': userId,
          'student_username': 'lightness2026',
          'student_level': 'Standard 4',
          'school': 'Riverside International',
        }),
      );

      print("Insert Status: ${insertRes.statusCode}");
      print("Insert Response: ${insertRes.body}");

      // Query parent_child_links again
      print("Querying links after insert attempt...");
      final queryRes = await http.get(
        Uri.parse("$urlBase/rest/v1/parent_child_links?select=*"),
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $token',
        },
      );

      if (queryRes.statusCode == 200) {
        final List links = jsonDecode(queryRes.body);
        print("Found ${links.length} links now:");
        for (var l in links) {
          print("  - Student: ${l['student_username']} | School: ${l['school']} | Grade: ${l['student_level']}");
        }
      } else {
        print("Failed to query links: ${queryRes.statusCode} - ${queryRes.body}");
      }
    } else {
      print("Login failed: ${loginRes.statusCode} - ${loginRes.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

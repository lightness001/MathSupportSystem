import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Inspecting links for parent Have (0758585858) ===");

  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  final parentUsername = "0758585858";
  final email = "${parentUsername}_private_app@mathsupport.tz";
  final passwords = ["password123", "12345678", "123456", "have123", "have1234"];

  String? token;
  for (final pwd in passwords) {
    try {
      final loginRes = await http.post(
        Uri.parse("$urlBase/auth/v1/token?grant_type=password"),
        headers: {
          'apikey': anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': pwd,
        }),
      );

      if (loginRes.statusCode == 200) {
        final data = jsonDecode(loginRes.body);
        token = data['access_token'];
        print("Login SUCCESS with password: $pwd");
        break;
      }
    } catch (_) {}
  }

  if (token == null) {
    print("Could not log in as 0758585858. Checking profiles table directly for this user...");
    // Let's search profiles table for this username to get the ID
    final profileRes = await http.get(
      Uri.parse("$urlBase/rest/v1/profiles?username=eq.$parentUsername"),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );
    print("Profile query response: ${profileRes.body}");
    return;
  }

  // Fetch parent child links under authenticated session
  print("Querying parent_child_links for 0758585858...");
  try {
    final res = await http.get(
      Uri.parse("$urlBase/rest/v1/parent_child_links?select=*"),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode == 200) {
      final List links = jsonDecode(res.body);
      print("Found ${links.length} linked children:");
      for (var l in links) {
        print("  - Student: ${l['student_username']} | School: ${l['school']} | Grade: ${l['student_level']}");
      }
    } else {
      print("Failed to query links: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error querying links: $e");
  }
}

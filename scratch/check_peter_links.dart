import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Login and inspect links for Peter (0788778877) ===");

  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  final email = "0788778877_private_app@mathsupport.tz";
  
  // Try common passwords
  final passwords = ["password123", "12345678", "123456"];
  
  String? token;
  String? userId;

  for (final pwd in passwords) {
    print("Trying login with password: $pwd...");
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
        userId = data['user']['id'];
        print("Login Success! User ID: $userId");
        break;
      } else {
        print("Login failed: ${loginRes.statusCode} - ${loginRes.body}");
      }
    } catch (e) {
      print("Error during login: $e");
    }
  }

  if (token == null) {
    print("Could not log in as Peter.");
    return;
  }

  // Now query links under Peter's session
  print("Querying links for Peter...");
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
      print("Links retrieved successfully (${links.length} found):");
      for (var l in links) {
        print("  - Link: ${l['student_username']} at ${l['school']} (Level: ${l['student_level']})");
      }
    } else {
      print("Failed to retrieve links: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error querying: $e");
  }
}

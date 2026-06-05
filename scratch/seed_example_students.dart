import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Seeding Example Students: Tommy, Emma, Alex ===");
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  final students = [
    {"username": "tommy", "name": "Tommy", "level": "Standard 7"},
    {"username": "emma", "name": "Emma", "level": "Standard 4"},
    {"username": "alex", "name": "Alex", "level": "Standard 7"},
  ];

  for (final s in students) {
    final username = s['username']!;
    final name = s['name']!;
    final level = s['level']!;
    final email = "${username}_private_app@mathsupport.tz";
    final password = "password123";

    print("\nProcessing student $name ($username)...");

    // 1. Try to sign up the student
    try {
      final signupRes = await http.post(
        Uri.parse("$urlBase/auth/v1/signup"),
        headers: {
          'apikey': anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      print("  Signup status: ${signupRes.statusCode}");
      if (signupRes.statusCode == 200 || signupRes.statusCode == 201) {
        final data = jsonDecode(signupRes.body);
        final String accessToken = data['access_token'];
        final String userId = data['user']['id'];
        print("  Signup SUCCESS! User ID: $userId");

        // 2. Create profile row
        final profileRes = await http.post(
          Uri.parse("$urlBase/rest/v1/profiles"),
          headers: {
            'apikey': anonKey,
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'id': userId,
            'full_name': name,
            'role': 'student',
            'username': username,
            'level': level,
          }),
        );
        print("  Profile Insert Status: ${profileRes.statusCode}");
      } else {
        print("  Signup skipped or failed: ${signupRes.body}");
      }
    } catch (e) {
      print("  Error processing $name: $e");
    }
  }

  print("\n=== Seeding completed! ===");
}

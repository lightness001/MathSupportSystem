import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Login and inspect links for all parents ===");

  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  final parents = [
    {"username": "0758509938", "name": "Asa"},
    {"username": "0758509911", "name": "Amina"},
    {"username": "0758509922", "name": "Dora"},
    {"username": "0758509933", "name": "Teo"},
    {"username": "0758509955", "name": "sisi"},
    {"username": "0758509966", "name": "tola"},
    {"username": "0758509977", "name": "pio"},
    {"username": "0758509999", "name": "Anna"},
    {"username": "0758509903", "name": "Jose"},
    {"username": "0755665566", "name": "Anna"},
    {"username": "0788778877", "name": "Peter"},
    {"username": "0712121212", "name": "John"},
  ];

  final passwords = ["password123", "12345678", "123456"];

  for (final p in parents) {
    final username = p['username']!;
    final name = p['name']!;
    final email = "${username}_private_app@mathsupport.tz";
    
    print("\n--- Checking parent $name ($username) ---");
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
          print("  Login success with password: $pwd");
          break;
        }
      } catch (_) {}
    }

    if (token == null) {
      print("  Could not log in as $name.");
      continue;
    }

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
        print("  Found ${links.length} links:");
        for (var l in links) {
          print("    * Child: ${l['student_username']} | School: ${l['school']} | Level: ${l['student_level']}");
        }
      } else {
        print("  Failed to query links: ${res.statusCode}");
      }
    } catch (e) {
      print("  Error: $e");
    }
  }

  print("\n=== Inspection completed ===");
}

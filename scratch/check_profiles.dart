import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Querying all profiles from DB ===");
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  try {
    final res = await http.get(
      Uri.parse("$urlBase/rest/v1/profiles?select=*"),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );

    if (res.statusCode == 200) {
      final List profiles = jsonDecode(res.body);
      print("Profiles (${profiles.length} found):");
      for (var p in profiles) {
        print("  - ${p['id']} | ${p['username']} | ${p['full_name']} | Role: ${p['role']} | Level: ${p['level']} | School: ${p['school']}");
      }
    } else {
      print("Failed to retrieve profiles: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error querying: $e");
  }
}

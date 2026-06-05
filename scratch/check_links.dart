import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Querying all parent_child_links from DB ===");
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  try {
    final res = await http.get(
      Uri.parse("$urlBase/rest/v1/parent_child_links?select=*"),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );

    if (res.statusCode == 200) {
      final List links = jsonDecode(res.body);
      print("Links (${links.length} found):");
      for (var l in links) {
        print("  - ParentID: ${l['parent_id']} | StudentUsername: ${l['student_username']} | School: ${l['school']} | Level: ${l['student_level']}");
      }
    } else {
      print("Failed to retrieve links: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error querying: $e");
  }
}

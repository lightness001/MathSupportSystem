import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("Connecting to Supabase REST API directly for parent_child_links...");
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/parent_child_links?select=*";
  
  final headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  };

  try {
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode == 200) {
      final List links = jsonDecode(res.body);
      print("Found ${links.length} total parent-child links in database:");
      for (var l in links) {
        print("  - Link ID: ${l['id']} | Parent ID: ${l['parent_id']} | Student: ${l['student_username']} | Level: ${l['student_level']} | School: ${l['school']}");
      }
    } else {
      print("Failed to query parent_child_links: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("Connecting to Supabase REST API directly...");
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/parent_child_links?select=*";
  final profilesUrl = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/profiles?select=*&role=eq.parent";
  
  final headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  };

  try {
    print("\n--- QUERYING PARENT PROFILES ---");
    final pRes = await http.get(Uri.parse(profilesUrl), headers: headers);
    if (pRes.statusCode == 200) {
      final List parents = jsonDecode(pRes.body);
      print("Found ${parents.length} parent profiles:");
      for (var p in parents) {
        print("  - ID: ${p['id']} | Name: ${p['full_name']} | Username: ${p['username']}");
      }
    } else {
      print("Failed to query profiles: ${pRes.statusCode} - ${pRes.body}");
    }

    print("\n--- QUERYING PARENT-CHILD LINKS ---");
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode == 200) {
      final List links = jsonDecode(res.body);
      print("Found ${links.length} total parent-child links in database:");
      for (var link in links) {
        print("  - Link ID: ${link['id']} | Parent ID: ${link['parent_id']} | Child: ${link['student_username']} | Level: ${link['student_level']} | School: ${link['school']}");
      }
    } else {
      print("Failed to query parent-child links: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error during direct HTTP fetch: $e");
  }
}

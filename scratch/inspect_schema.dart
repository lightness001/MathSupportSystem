import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  };

  try {
    print("Fetching first student profile...");
    final studentRes = await http.get(Uri.parse("https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/profiles?role=eq.student&limit=1"), headers: headers);
    if (studentRes.statusCode == 200) {
      print("Student: ${studentRes.body}");
    }

    print("\nFetching first parent profile...");
    final parentRes = await http.get(Uri.parse("https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/profiles?role=eq.parent&limit=1"), headers: headers);
    if (parentRes.statusCode == 200) {
      print("Parent: ${parentRes.body}");
    }

    print("\nFetching first parent_child_link...");
    final linkRes = await http.get(Uri.parse("https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/parent_child_links?limit=1"), headers: headers);
    if (linkRes.statusCode == 200) {
      print("Link: ${linkRes.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

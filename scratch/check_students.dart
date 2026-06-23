import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/profiles?select=*&role=eq.student";
  final headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  };

  try {
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode == 200) {
      final List students = jsonDecode(res.body);
      print("Found ${students.length} student profiles:");
      for (var s in students) {
        print("  - Username: ${s['username']} | Name: ${s['full_name']} | Level: ${s['level']}");
      }
    } else {
      print("Failed to fetch students: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

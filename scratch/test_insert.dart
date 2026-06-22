import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/parent_child_links";
  final headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final body = jsonEncode({
    'parent_id': '57a290c3-f19f-4f07-9566-4a4d43ed0834', // Asa's ID
    'student_username': 'lightness2026',
    'student_level': 'Standard 4',
    'school': 'Riverside International',
  });

  try {
    print("Attempting to insert test row into parent_child_links...");
    final res = await http.post(Uri.parse(url), headers: headers, body: body);
    print("Response Status: ${res.statusCode}");
    print("Response Body: ${res.body}");
  } catch (e) {
    print("Insert error: $e");
  }
}

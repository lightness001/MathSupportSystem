import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/profiles?select=*&limit=1";
  final headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  };

  try {
    // Let's test if there is a "schools" or "institutions" endpoint
    final testSchools = await http.get(Uri.parse("https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/schools?select=*"), headers: headers);
    print("Schools endpoint status: ${testSchools.statusCode}");
    if (testSchools.statusCode == 200) {
      print("Schools data: ${testSchools.body}");
    }
  } catch (e) {
    print("Error checking schools table: $e");
  }
}

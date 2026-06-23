import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/";

  print("Fetching schema...");
  try {
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final paths = data['paths'] as Map<String, dynamic>;
      print("Available database paths:");
      for (var path in paths.keys) {
        print("  - $path");
      }
    } else {
      print("Failed: ${res.statusCode} ${res.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

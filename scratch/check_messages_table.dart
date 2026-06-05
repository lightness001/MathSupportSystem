import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/messages?select=*&limit=1";

  print("Querying 'messages' table...");
  try {
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );
    print("Messages Status: ${res.statusCode}");
    print("Messages Body: ${res.body}");
  } catch (e) {
    print("Error: $e");
  }
}

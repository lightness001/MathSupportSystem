import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Fetching PostgREST OpenAPI Spec to list all Tables & RPCs ===");
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  try {
    final rootRes = await http.get(
      Uri.parse("$urlBase/rest/v1/"),
      headers: {
        'apikey': anonKey,
      },
    );
    if (rootRes.statusCode == 200) {
      final spec = jsonDecode(rootRes.body);
      final paths = spec['paths'] as Map<String, dynamic>;
      print("\nAvailable database endpoints/tables/RPCs:");
      for (var path in paths.keys) {
        print("  - $path");
      }
    } else {
      print("Failed to fetch spec: ${rootRes.statusCode} - ${rootRes.body}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

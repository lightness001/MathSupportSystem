import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Testing RPC endpoints ===");
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/rpc";

  final testRpcs = ["get_policies", "exec_sql", "execute_sql", "sql", "run_sql", "query"];

  for (final rpc in testRpcs) {
    try {
      print("Testing RPC: $rpc...");
      final res = await http.post(
        Uri.parse("$urlBase/$rpc"),
        headers: {
          'apikey': anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sql': 'select 1;',
          'query': 'select 1;',
        }),
      );
      print("  Status: ${res.statusCode}");
      print("  Response: ${res.body}");
    } catch (e) {
      print("  Error: $e");
    }
  }
}

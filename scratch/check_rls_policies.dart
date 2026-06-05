import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Querying RLS Policies for parent_child_links ===");

  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final url = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/rpc/get_policies";
  
  // Let's try querying standard postgres catalog for policies using Direct REST if possible
  // Wait, does direct REST allow querying pg_policies?
  // Let's try querying the pg_catalog via direct REST RPC if there is one, or check if we can query pg_policies via REST view.
  // Actually, standard postgrest doesn't expose views of pg_catalog by default unless custom RPC is added.
  // But we can check policies by simulating different authenticated and unauthenticated queries!

  // Let's simulate an insert from a guest user to see what error it returns.
  final testParentId = "6cac94c0-de5a-4264-839a-129e603628a4"; // Peter's profile ID
  final insertUrl = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/parent_child_links";

  print("Simulating anonymous insert to parent_child_links...");
  try {
    final res = await http.post(
      Uri.parse(insertUrl),
      headers: {
        'apikey': anonKey,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode({
        'parent_id': testParentId,
        'student_username': 'anna2026',
        'student_level': 'Standard 7',
        'school': 'Test School',
      }),
    );
    print("Anon Insert Status: ${res.statusCode}");
    print("Anon Insert Response: ${res.body}");
  } catch (e) {
    print("Error during anon insert: $e");
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final supabaseUrl = "https://wnxeohqejdiytqkxdcwe.supabase.co";
  final apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';

  final phone = "0700000002";
  final email = "${phone}_private_app@mathsupport.tz";
  final password = "password123";

  try {
    print("1. Signing up a new parent via Auth API...");
    final signupUrl = "$supabaseUrl/auth/v1/signup";
    final signupRes = await http.post(
      Uri.parse(signupUrl),
      headers: {
        'apikey': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    print("Signup Status: ${signupRes.statusCode}");
    if (signupRes.statusCode != 200 && signupRes.statusCode != 201) {
      print("Signup response: ${signupRes.body}");
      return;
    }

    final signupJson = jsonDecode(signupRes.body);
    final String accessToken = signupJson['access_token'];
    final String userId = signupJson['user']['id'];
    print("Signup success! User ID: $userId");

    // 2. Create the parent profile
    print("\n2. Creating profile row...");
    final profileRes = await http.post(
      Uri.parse("$supabaseUrl/rest/v1/profiles"),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode({
        'id': userId,
        'full_name': 'Test Parent HTTP',
        'role': 'parent',
        'username': phone,
        'level': 'Parent',
      }),
    );
    print("Profile Insert Status: ${profileRes.statusCode}");
    print("Profile Insert Response: ${profileRes.body}");

    // 3. Insert parent-child link
    print("\n3. Inserting parent-child link...");
    final linkRes = await http.post(
      Uri.parse("$supabaseUrl/rest/v1/parent_child_links"),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode({
        'parent_id': userId,
        'student_username': 'anna2026',
        'student_level': 'Standard 7',
        'school': 'Westfield Academy',
      }),
    );
    print("Link Insert Status: ${linkRes.statusCode}");
    print("Link Insert Response: ${linkRes.body}");

    // 4. Query links
    print("\n4. Querying links...");
    final queryRes = await http.get(
      Uri.parse("$supabaseUrl/rest/v1/parent_child_links?select=*"),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $accessToken',
      },
    );
    print("Query Status: ${queryRes.statusCode}");
    print("Query Response: ${queryRes.body}");

  } catch (e) {
    print("Error: $e");
  }
}

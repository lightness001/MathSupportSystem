import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("=== Parent Registration & Sync Integration Test ===");

  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co";

  // Step 1: Generate a unique test parent phone number
  final parentPhone = "0700${(DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}";
  final parentPhone = "0700" + (DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
  final parentEmail = "${parentPhone}_private_app@mathsupport.tz";
  final parentPassword = "password123";
  final parentName = "Test Parent Integrator";

  print("Parent Phone: $parentPhone");
  print("Parent Email: $parentEmail");

  // Step 2: Sign Up Parent in Auth
  print("\n1. Signing up parent in Auth...");
  String? userId;
  try {
    final signupRes = await http.post(
      Uri.parse("$urlBase/auth/v1/signup"),
      headers: {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': parentEmail,
        'password': parentPassword,
      }),
    );

    if (signupRes.statusCode == 200 || signupRes.statusCode == 201) {
      final data = jsonDecode(signupRes.body);
      userId = data['id'] ?? data['user']?['id'];
      print("Sign Up Success! User ID: $userId");
    } else {
      print("Sign Up failed: ${signupRes.statusCode} - ${signupRes.body}");
      return;
    }
  } catch (e) {
    print("Sign up error: $e");
    return;
  }

  // Step 3: Log In first to establish authenticated session
  print("\n2. Logging in as parent to get auth token...");
  String? token;
  try {
    final loginRes = await http.post(
      Uri.parse("$urlBase/auth/v1/token?grant_type=password"),
      headers: {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': parentEmail,
        'password': parentPassword,
      }),
    );

    if (loginRes.statusCode == 200) {
      final data = jsonDecode(loginRes.body);
      token = data['access_token'];
      print("Login success!");
    } else {
      print("Login failed: ${loginRes.statusCode} - ${loginRes.body}");
      return;
    }
  } catch (e) {
    print("Login error: $e");
    return;
  }

  // Step 4: Insert parent profile under authenticated session
  print("\n3. Inserting parent profile into 'profiles' table with auth token...");
  try {
    final profileRes = await http.post(
      Uri.parse("$urlBase/rest/v1/profiles"),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'id': userId,
        'full_name': parentName,
        'role': 'parent',
        'username': parentPhone,
        'level': 'Parent',
      }),
    );

    if (profileRes.statusCode == 201 || profileRes.statusCode == 200) {
      print("Profile insert success!");
    } else {
      print("Profile insert failed: ${profileRes.statusCode} - ${profileRes.body}");
      return;
    }
  } catch (e) {
    print("Profile insert error: $e");
    return;
  }

  // Step 5: Sync children links to Supabase under authenticated parent session
  print("\n4. Syncing children links to Supabase...");
  final List children = [
    {
      'username': 'anna2026',
      'school': 'Westfield Academy',
      'level': 'Standard 7',
    },
    {
      'username': 'lightness2026',
      'school': 'Riverside International',
      'level': 'Standard 4',
    }
  ];
  bool allSuccessful = true;

  for (var child in children) {
    final String username = child['username']!;
    final String school = child['school']!;
    final String level = child['level']!;

    print("Syncing child '$username' with school '$school'...");
    try {
      final syncRes = await http.post(
        Uri.parse("$urlBase/rest/v1/parent_child_links"),
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'parent_id': userId,
          'student_username': username,
          'student_level': level,
          'school': school,
        }),
      );

      if (syncRes.statusCode == 201 || syncRes.statusCode == 200) {
        print("  Sync success for child '$username'!");
      } else {
        print("  Sync failed for child '$username': ${syncRes.statusCode} - ${syncRes.body}");
        allSuccessful = false;
      }
    } catch (e) {
      print("  Sync error for child '$username': $e");
      allSuccessful = false;
    }
  }

  if (allSuccessful) {
    print("\nALL LINKS SYNCED SUCCESSFULLY!");
  } else {
    print("\nSOME OR ALL LINKS FAILED TO SYNC.");
  }

  // Step 6: Fetch and verify links
  print("\n5. Retrieving linked children under parent's session to verify dynamic select...");
  try {
    final res = await http.get(
      Uri.parse("$urlBase/rest/v1/parent_child_links?select=*"),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode == 200) {
      final List links = jsonDecode(res.body);
      print("VERIFIED LINKS RETRIEVED (${links.length} found):");
      for (var l in links) {
        print("  - Student: ${l['student_username']} | School: ${l['school']} | Grade: ${l['student_level']}");
      }
    } else {
      print("Verification fetch failed: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print("Verification fetch error: $e");
  }

  print("\n=== Integration Test Completed ===");
}

import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print("Initializing Supabase...");
  await Supabase.initialize(
    url: 'https://wnxeohqejdiytqkxdcwe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  );

  final client = Supabase.instance.client;

  // Let's sign in a parent
  // We'll try to sign in with an existing parent phone or register a new one to test.
  final testPhone = "0758509938"; // Asa's phone
  final email = "${testPhone}_private_app@mathsupport.tz";
  // We don't know the password, let's try to sign up a new parent instead!
  final newPhone = "0700000001";
  final newEmail = "${newPhone}_private_app@mathsupport.tz";
  final password = "password123";

  try {
    print("Signing up new parent: $newEmail...");
    final signUpRes = await client.auth.signUp(email: newEmail, password: password);
    print("Sign up success! User ID: ${signUpRes.user?.id}");

    final userId = signUpRes.user!.id;

    // Create profile
    print("Creating profile for parent...");
    await client.from('profiles').insert({
      'id': userId,
      'full_name': 'Test Parent',
      'role': 'parent',
      'username': newPhone,
      'level': 'Parent',
    });
    print("Profile created!");

    // Now try to insert a parent-child link for an existing student: anna2026
    print("Attempting to insert parent_child_link...");
    await client.from('parent_child_links').insert({
      'parent_id': userId,
      'student_username': 'anna2026',
      'student_level': 'Standard 7',
      'school': 'Westfield Academy',
    });
    print("Insert success!");

    // Let's query it back
    print("Querying links...");
    final links = await client.from('parent_child_links').select();
    print("Links found: $links");

  } catch (e) {
    print("ERROR encountered: $e");
  }
}

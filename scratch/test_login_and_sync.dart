import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print("Initializing Supabase...");
  await Supabase.initialize(
    url: 'https://wnxeohqejdiytqkxdcwe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  );

  final client = Supabase.instance.client;

  // Let's log in as the user we created: 0700000002
  final email = "0700000002_private_app@mathsupport.tz";
  final password = "password123";

  try {
    print("Signing in...");
    final res = await client.auth.signInWithPassword(email: email, password: password);
    print("Sign in success! User ID: ${res.user?.id}");

    final user = res.user!;

    // Query profiles to verify we can read it
    final profile = await client.from('profiles').select().eq('id', user.id).single();
    print("Profile: $profile");

    // Now try to query parent_child_links
    print("Querying links...");
    final links = await client.from('parent_child_links').select().eq('parent_id', user.id);
    print("Links: $links");

    // Try inserting another child link
    print("Attempting to insert new child link...");
    await client.from('parent_child_links').insert({
      'parent_id': user.id,
      'student_username': 'lightness2026',
      'student_level': 'Standard 4',
      'school': 'Riverside International',
    });
    print("Insert success!");

    // Query again
    final links2 = await client.from('parent_child_links').select().eq('parent_id', user.id);
    print("Links after insert: $links2");

  } catch (e) {
    print("Error: $e");
  }
}

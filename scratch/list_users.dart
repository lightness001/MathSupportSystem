import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://wnxeohqejdiytqkxdcwe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  );

  final supabase = Supabase.instance.client;
  
  try {
    final profiles = await supabase
        .from('profiles')
        .select('username, email, role, level, school');
    
    print('--- PROFILES ---');
    for (var p in profiles) {
      print('Username/Email: ${p['username'] ?? p['email']}, Role: ${p['role']}, Level: ${p['level']}, School: ${p['school']}');
    }
  } catch (e) {
    print('Error listing profiles: $e');
  }
}

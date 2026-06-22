import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print("Initializing Supabase...");
  await Supabase.initialize(
    url: 'https://wnxeohqejdiytqkxdcwe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  );
  
  final client = Supabase.instance.client;
  
  print("\n--- FETCHING LATEST HOMEWORKS ---");
  final homeworks = await client.from('homeworks').select().order('created_at', ascending: false).limit(5);
  for (var hw in homeworks) {
    print("ID: ${hw['id']}");
    print("Title: ${hw['title']}");
    print("Description: ${hw['description']}");
    print("File URL: ${hw['file_url']}");
    print("Questions JSON: ${hw['questions']}");
    print("-----------------------------------");
  }

  print("\n--- FETCHING LATEST SUBMISSIONS ---");
  final submissions = await client.from('submissions').select().order('created_at', ascending: false).limit(5);
  for (var sub in submissions) {
    print("ID: ${sub['id']}");
    print("Homework ID: ${sub['homework_id']}");
    print("Student ID: ${sub['student_id']}");
    print("Content: ${sub['content']}");
    print("-----------------------------------");
  }

  print("\n--- FETCHING LATEST RESULTS ---");
  final results = await client.from('results').select().order('created_at', ascending: false).limit(5);
  for (var res in results) {
    print("ID: ${res['id']}");
    print("Submission ID: ${res['submission_id']}");
    print("Score: ${res['score']}");
    print("Feedback: ${res['feedback']}");
    print("-----------------------------------");
  }
}

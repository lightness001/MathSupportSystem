import 'dart:convert';
import 'dart:io';

void main() async {
  print("Testing if 'parent_feedback' column exists in 'results'...");
  final url = Uri.parse('https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1/results?id=eq.1');
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';

  final client = HttpClient();
  try {
    final request = await client.patchUrl(url);
    request.headers.set('apikey', anonKey);
    request.headers.set('Authorization', 'Bearer $anonKey');
    request.headers.set('Content-Type', 'application/json');
    
    final payload = {
      'parent_feedback': 'test feedback'
    };
    
    request.write(jsonEncode(payload));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    print("Status code: ${response.statusCode}");
    print("Response body: $responseBody");
  } catch (e) {
    print("Error: $e");
  } finally {
    client.close();
  }
}

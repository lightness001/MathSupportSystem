import 'package:http/http.dart' as http;

void main() async {
  final anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0';
  final urlBase = "https://wnxeohqejdiytqkxdcwe.supabase.co/rest/v1";

  final candidateTables = [
    'chats',
    'chat',
    'conversations',
    'conversation',
    'parent_chats',
    'messages',
    'message',
    'teacher_chats',
    'teacher_records'
  ];

  for (var table in candidateTables) {
    try {
      final res = await http.get(
        Uri.parse("$urlBase/$table?select=*&limit=1"),
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        },
      );
      print("Table '$table': ${res.statusCode}");
    } catch (e) {
      print("Table '$table' Error: $e");
    }
  }
}

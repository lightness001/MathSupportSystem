import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/assessment_engine.dart';

class ParentNotificationsScreen extends StatelessWidget {
  final String childName;

  const ParentNotificationsScreen({super.key, required this.childName});

  Future<List<Map<String, dynamic>>> _fetchActivityFeed() async {
    if (childName.isEmpty) return [];

    final supabase = Supabase.instance.client;
    final List<Map<String, dynamic>> feed = [];

    try {
      // 1. Fetch child ID and Level
      final studentRes = await supabase.from('profiles').select('id, level').eq('username', childName).single();
      final String studentId = studentRes['id'];
      final String level = studentRes['level'] ?? 'Standard 7';

      // 2. Fetch Recent Graded Results
      final resultsRes = await supabase.from('results').select('''
            score, created_at, submissions!inner(homework!inner(title))
          ''').eq('submissions.student_id', studentId).order('created_at', ascending: false).limit(5);
      
      for (var r in (resultsRes as List)) {
        feed.add({
          'type': 'grade',
          'title': 'Homework Graded',
          'body': '$childName scored ${(r['score'] as num).toInt()}% in ${r['submissions']['homework']['title']}',
          'date': DateTime.parse(r['created_at']),
          'icon': Icons.grade,
          'color': Colors.green,
        });
      }

      // 3. Fetch New Homework for this Level
      final homeworkRes = await supabase.from('homework').select('title, created_at').eq('level', level).order('created_at', ascending: false).limit(5);
      
      for (var hw in (homeworkRes as List)) {
        feed.add({
          'type': 'homework',
          'title': 'New Assignment Posted',
          'body': 'A new ${hw['title']} task is available for $level.',
          'date': DateTime.parse(hw['created_at']),
          'icon': Icons.assignment_late,
          'color': Colors.blue,
        });
      }

      // Sort combined feed by date
      feed.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      return feed;
    } catch (e) {
      debugPrint("Feed error: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("Live Activity Feed", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchActivityFeed(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final feed = snapshot.data ?? [];

                if (feed.isEmpty) return const Center(child: Text("No recent activity for this child.", style: TextStyle(color: Colors.grey)));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: feed.length,
                  itemBuilder: (context, index) {
                    final item = feed[index];
                    final String timeLabel = DateFormat.yMMMd().add_jm().format(item['date']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(backgroundColor: (item['color'] as Color).withOpacity(0.1), child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 20)),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(item['body'], style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                                const SizedBox(height: 8),
                                Text(timeLabel, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}